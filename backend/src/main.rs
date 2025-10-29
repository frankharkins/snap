use std::sync::Arc;

use papaya::{HashMap, OccupiedError};
use serde::{Deserialize, Serialize};

use warp::Filter;

mod game;
mod manager;
mod message;
mod websocket;

const MAX_NUM_GAMES: usize = 1000;

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
    GameDestroyed,
    ServerFull,
    UserAlreadyConnected,
    GameNotFound,
    GameStarted { your_number: game::PlayerNumber },
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

    let index = warp::path::end().and(
        warp::fs::file("../frontend/index.html")
    );
    let index_js = warp::path("main.js").and(
        warp::fs::file("../frontend/main.js")
    );
    let index_css = warp::path("main.css").and(
        warp::fs::file("../frontend/main.css")
    );
    let images = warp::path("snap").and(warp::path("images")).and(
        warp::fs::dir ("../frontend/images")
    );
    let routes = index.or(index_js).or(index_css).or(images).or(create).or(join);

    warp::serve(routes).run(([0, 0, 0, 0], 3030)).await;
}

async fn create(ws: warp::ws::WebSocket, state: Arc<ServerState>) {
    println!("Creating new game");
    match state.manager.create().await {
        Ok(users) => {
            let (this_user, other_user) = (users[0], users[1]);
            let ws_handler = create_linked_websocket(this_user, ws, &state);
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
            send_message_and_close(ws, OutputMessageType::ServerFull);
        }
    }
}

async fn join(user_id: usize, ws: warp::ws::WebSocket, state: Arc<ServerState>) {
    let Ok(all_players_in_game) = state.manager.get_players(user_id).await else {
        send_message_and_close(ws, OutputMessageType::GameNotFound);
        return;
    };
    let users_map = state.users.pin();
    match users_map.contains_key(&user_id) {
        true => {
            send_message_and_close(ws, OutputMessageType::UserAlreadyConnected);
            return;
        }
        false => {
            let ws_handler = create_linked_websocket(user_id, ws, &state);
            users_map.insert(user_id, ws_handler);

            // Let everyone know the game has started
            for (your_number, player_id) in all_players_in_game.into_iter().enumerate() {
                let Some(ws_handler) = users_map.get(&player_id) else { break; };
                _ = ws_handler.send(OutputMessageType::GameStarted { your_number });
            }
        }
    };
}

/// Create a websocket linked to the user_id's game. Incoming messages will from
/// this websocket will affect the game, and closing the connection will destroy
/// the game.
fn create_linked_websocket(
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

/// Use this for websockets that should not be connected to a game, and instead
/// closed with a message.
fn send_message_and_close(ws: warp::ws::WebSocket, message: OutputMessageType) {
    let ws_handler = WebSocketHandler::new(ws, 0, async |_| {}, async || {});
    _ = ws_handler.send(message);
    ws_handler.close();
}

async fn send_message(message: OutputMessage, state: Arc<ServerState>) {
    match state.users.pin().get(&message.recipient) {
        None => return,
        Some(websocket_handler) => _ = websocket_handler.send(message.message),
    };
}

async fn user_disconnected(user_id: usize, state: Arc<ServerState>) {
    let Ok(users_to_drop) = state.manager.destroy_users_game(user_id).await else {
        // This can happen if the user was never part of a game
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
