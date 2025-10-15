use std::sync::Arc;

use futures_util::SinkExt;

use papaya::{HashMap, OccupiedError};
use serde::{Deserialize, Serialize};

use warp::Filter;

mod game;
mod manager;
mod message;
mod websocket;

const MAX_NUM_GAMES: usize = 3;

type SnapManager = manager::SessionManager<game::Snap>;
type WebSocketHandler = websocket::WebSocketHandler<InputMessageType, OutputMessageType>;
type WebSocketMap = HashMap<usize, WebSocketHandler>;

// Input / output messages
struct ServerState {
    manager: SnapManager,
    users: WebSocketMap,
}

type OutputMessage = message::OutputMessage<usize, OutputMessageType>;

#[derive(Debug, Deserialize, Serialize)]
enum OutputMessageType {
    GameCreated { other_player_id: usize },
    OtherUserJoined,
    GameDestroyed,
    ServerFull,
    UserAlreadyConnected,
    GameUpdate(game::OutputMessageType),
}

#[derive(Debug, Deserialize, Serialize)]
enum InputMessageType {
    GameUpdate(game::InputMessageType),
}

#[tokio::main]
async fn main() {
    let server_state = Arc::new(ServerState {
        manager: SnapManager::new(MAX_NUM_GAMES),
        users: WebSocketMap::default(),
    });

    let state = move || {
        let cloned = server_state.clone();
        warp::any().map(move || cloned.clone())
    };

    // Route to create a new game
    let create = warp::path!("create").and(warp::ws()).and(state()).map(
        |ws: warp::ws::Ws, state: Arc<ServerState>| {
            // This will call our function if the handshake succeeds.
            ws.on_upgrade(move |socket| create(socket, state))
        },
    );

    let join = warp::path!("join" / usize)
        .and(warp::ws())
        .and(state())
        .map(
            |user_id: usize, ws: warp::ws::Ws, state: Arc<ServerState>| {
                // This will call our function if the handshake succeeds.
                ws.on_upgrade(move |socket| join(user_id, socket, state))
            },
        );

    // let routes = index.or(index_js).or(index_css).or(images).or(snap);
    let index = warp::path::end().map(|| warp::reply::html(""));
    let routes = index.or(create).or(join);

    warp::serve(routes).run(([0, 0, 0, 0], 3030)).await;
}

async fn create(mut ws: warp::ws::WebSocket, state: Arc<ServerState>) {
    match state.manager.create().await {
        Ok(users) => {
            let (this_user, other_user) = (users[0], users[1]);
            let ws_handler = create_websocket_handler(this_user, ws, &state);
            match state.users.pin().try_insert(this_user, ws_handler) {
                Ok(handler_ref) => {
                    // Let the user know the connection was successful and give them the
                    // ID of the other player so they can connect.
                    _ = handler_ref.send(OutputMessageType::GameCreated {
                        other_player_id: other_user,
                    });
                }
                Err(OccupiedError {
                    current: _,
                    not_inserted,
                }) => {
                    // This should never happen
                    println!("Conflict with create user");
                    not_inserted.close();
                }
            };
        }
        Err(manager::CreateGameError::ServerFull) => {
            // Manually send one-off message then drop the connection.
            // No cleanup needed.
            let message = "{\"ServerFull\":null}";
            _ = ws.send(warp::ws::Message::text(message)).await;
        }
    }
}

async fn join(user_id: usize, ws: warp::ws::WebSocket, state: Arc<ServerState>) {
    let ws_handler = create_websocket_handler(user_id, ws, &state);
    match state.users.pin().try_insert(user_id, ws_handler) {
        Ok(handler_ref) => {
            // TODO: Send OtherUserJoined message and have client wait for it.
            // Otherwise, first user can draw cards before the other user joins.
        }
        Err(OccupiedError {
            current: _,
            not_inserted,
        }) => {
            _ = not_inserted.send(OutputMessageType::UserAlreadyConnected);
            not_inserted.close();
        }
    };
}

fn create_websocket_handler(
    user_id: usize,
    ws: warp::ws::WebSocket,
    state: &Arc<ServerState>,
) -> WebSocketHandler {
    let on_message = {
        let cloned_state = state.clone();
        move |msg| handle_message(msg, user_id, cloned_state.clone())
    };
    let on_disconnect = {
        let cloned_state = state.clone();
        move || user_disconnected(user_id, cloned_state.clone())
    };
    WebSocketHandler::new(ws, user_id, on_message, on_disconnect)
}

async fn send_message(message: OutputMessage, state: Arc<ServerState>) {
    match state.users.pin().get(&message.recipient) {
        None => return,
        Some(websocket_handler) => _ = websocket_handler.send(message.message),
    };
}

async fn user_disconnected(user_id: usize, state: Arc<ServerState>) {
    let Ok(users_to_drop) = state.manager.destroy_users_game(user_id).await else {
        // No idea how to recover from this
        println!("Failed to destroy game :/");
        return;
    };
    let users_map = state.users.pin();
    for user in users_to_drop.iter() {
        if let Some(websocket_output) = users_map.remove(user) {
            websocket_output.close();
        }
    }
}

async fn handle_message(message: InputMessageType, sender: usize, state: Arc<ServerState>) {
    match message {
        InputMessageType::GameUpdate(message) => {
            let game_message = message::InputMessage { message, sender };
            let Ok(game_responses) = state.manager.handle_message(game_message).await else {
                return;
            };
            let responses = game_responses.iter().map(|r| OutputMessage {
                message: OutputMessageType::GameUpdate(r.message),
                recipient: r.recipient,
            });
            for response in responses {
                send_message(response, state.clone()).await;
            }
        }
    };
}
