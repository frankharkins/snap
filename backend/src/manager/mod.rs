use papaya::HashMap;
use std::sync::atomic::AtomicUsize;
use tokio::sync::RwLock;

use crate::message;

pub trait Game {
    type InputMessage;
    type OutputMessage;
    const NUM_PLAYERS: usize;

    fn player_action(
        &mut self,
        message: message::InputMessage<usize, Self::InputMessage>,
    ) -> Vec<message::OutputMessage<usize, Self::OutputMessage>>;
}

type UserId = usize;
type GameId = usize;

/// Manages game sessions: Essentially mapping user IDs to player numbers and
/// creating/destroying games as needed in an async way.
pub struct SessionManager<G: Game + Default> {
    games: Vec<RwLock<Option<GameContainer<G>>>>,
    freelist: RwLock<Vec<GameId>>,
    users: HashMap<UserId, GameRef>,
    id_counter: AtomicUsize,
}

impl<G: Game + Default> SessionManager<G> {
    pub fn new(max_num_games: usize) -> Self {
        Self {
            games: Vec::from_iter((0..max_num_games).map(|_| RwLock::new(None))),
            freelist: RwLock::new((0..max_num_games).collect()),
            users: HashMap::default(),
            id_counter: AtomicUsize::new(1),
        }
    }

    /// Create a new ID, unique to this manager instance
    fn new_id(&self) -> usize {
        self.id_counter
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    }

    fn new_game(&self, users: Vec<UserId>) -> GameContainer<G> {
        GameContainer {
            game: G::default(),
            id: self.new_id(),
            users,
        }
    }

    pub async fn create(&self) -> Result<NewGame, CreateGameError> {
        // Wait for lock on freelist
        let mut freelist = self.freelist.write().await;
        let Some(next_available_slot) = freelist.pop() else {
            return Err(CreateGameError::ServerFull);
        };
        drop(freelist);

        // Generate new IDs for the players of this game
        let users: Vec<UserId> = (0..G::NUM_PLAYERS).map(|_| self.new_id()).collect();

        // Make a new game and create a reference to it
        let new_game = self.new_game(users.clone());
        let game_ref = GameRef {
            index: next_available_slot,
            id: new_game.id,
        };

        // Replace the slot with the new game
        self.games[next_available_slot]
            .write()
            .await
            .replace(new_game);

        // Update the users hashmap
        let user_map = self.users.pin();
        for user in users.iter() {
            user_map.insert(*user, game_ref);
        }

        // Return the user IDs so players can send messages to the game
        Ok(users)
    }

    pub async fn handle_message(
        &self,
        message: message::InputMessage<usize, G::InputMessage>,
    ) -> Result<Vec<message::OutputMessage<usize, G::OutputMessage>>, HandleMessageError> {
        let Some(&game_ref) = self.users.pin().get(&message.sender).clone() else {
            return Err(HandleMessageError::GameDoesNotExist);
        };
        let mut game_slot = self.games[game_ref.index].write().await;
        let Some(game_container) = game_slot.as_mut() else {
            return Err(HandleMessageError::GameDoesNotExist);
        };
        if game_container.id != game_ref.id {
            return Err(HandleMessageError::GameDoesNotExist);
        }

        // Ok; game exists and we have a lock on the slot
        let Some(sender_player_number) = game_container
            .users
            .iter()
            .position(|i| *i == message.sender)
        else {
            return Err(HandleMessageError::UnexpectedError);
        };
        let responses = game_container.game.player_action(message::InputMessage {
            sender: sender_player_number,
            message: message.message,
        });
        let mapped_responses: Option<Vec<message::OutputMessage<usize, G::OutputMessage>>> =
            responses
                .into_iter()
                .map(
                    |message| match game_container.users.get(message.recipient) {
                        Some(&user_id) => Some(message::OutputMessage {
                            recipient: user_id,
                            message: message.message,
                        }),
                        None => None,
                    },
                )
                .collect();

        match mapped_responses {
            Some(responses) => Ok(responses),
            None => Err(HandleMessageError::UnexpectedError),
        }
    }

    /// Get a IDs of players in the same game
    pub async fn get_players(&self, user: UserId) -> Result<Vec<UserId>, ()> {
        let Some(&game_ref) = self.users.pin().get(&user) else {
            // User does not currently exist
            return Err(());
        };
        match self.games[game_ref.index].read().await.as_ref() {
            Some(game_container) => Ok(game_container.users.clone()),
            None => Err(()),
        }
    }

    /// Destroy a game and return vec of users to notify
    pub async fn destroy_users_game(&self, user: UserId) -> Result<Vec<UserId>, DestroyGameError> {
        let Some(&game_ref) = self.users.pin().get(&user) else {
            // User does not currently exist
            return Err(DestroyGameError::UnexpectedError);
        };

        // Lock the slot
        let mut game_slot = self.games[game_ref.index].write().await;

        let Some(game_container) = game_slot.take() else {
            return Err(DestroyGameError::UnexpectedError);
        };
        if game_container.id != game_ref.id {
            // Game has already been destroyed and slot reused
            // Let's put the game back and return ok
            game_slot.replace(game_container);
            return Ok(vec![]);
        }

        // Remove users from hashmap
        {
            let users_map = self.users.pin();
            for user in game_container.users.iter() {
                users_map.remove(user);
            }
        }

        // Add the slot to the freelist
        self.freelist.write().await.push(game_ref.index);

        Ok(game_container.users)
    }
}

// Game creation
type NewGame = Vec<UserId>;
pub enum CreateGameError {
    ServerFull,
}
pub enum DestroyGameError {
    UnexpectedError,
}

// Handling player actions
pub enum HandleMessageError {
    GameDoesNotExist,
    UnexpectedError,
}

/// Reference to a game. Since we store all games in a Vec, the reference is the
/// index of that game in the Vec, plus the game's ID (in case the space has
/// been re-used by another game).
#[derive(Clone, Copy)]
struct GameRef {
    index: usize,
    id: GameId,
}

struct GameContainer<G: Game> {
    game: G,
    id: GameId,
    users: Vec<UserId>,
}

// TESTS

#[derive(Default)]
struct DummyGame {}

enum DummyInputMessage {
    UserSays(usize),
}
enum DummyOutputMessage {
    OtherUserSays(usize, usize),
}

impl Game for DummyGame {
    type InputMessage = DummyInputMessage;
    type OutputMessage = DummyOutputMessage;
    const NUM_PLAYERS: usize = 3;
    fn player_action(
        &mut self,
        message: message::InputMessage<usize, Self::InputMessage>,
    ) -> Vec<message::OutputMessage<usize, Self::OutputMessage>> {
        let DummyInputMessage::UserSays(num) = message.message;
        (0..Self::NUM_PLAYERS)
            .map(|i| message::OutputMessage {
                recipient: i,
                message: DummyOutputMessage::OtherUserSays(message.sender, num),
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn game_creation_ids_unique() {
        let manager: SessionManager<DummyGame> = SessionManager::new(5);
        let Ok(users_1) = manager.create().await else {
            panic!()
        };
        assert_eq!(users_1.len(), 3);
        let Ok(users_2) = manager.create().await else {
            panic!()
        };
        assert_eq!(users_2.len(), 3);

        assert!(users_1.iter().all(|id| !users_2.contains(id)));
    }

    #[tokio::test]
    async fn game_message_mapping() {
        let manager: SessionManager<DummyGame> = SessionManager::new(5);
        for _ in 0..2 {
            _ = manager.create().await;
        }
        let Ok(users) = manager.create().await else {
            panic!()
        };

        for sender in users.iter() {
            let msg = message::InputMessage {
                sender: *sender,
                message: DummyInputMessage::UserSays(99),
            };
            let Ok(responses) = manager.handle_message(msg).await else {
                panic!()
            };
            for response in responses {
                assert!(users.contains(&response.recipient));
                let DummyOutputMessage::OtherUserSays(_, num) = response.message;
                assert_eq!(num, 99);
            }
        }
    }

    #[tokio::test]
    async fn max_games_enforced() {
        let manager: SessionManager<DummyGame> = SessionManager::new(5);
        for _ in 0..5 {
            let Ok(_) = manager.create().await else {
                panic!()
            };
        }
        let Err(CreateGameError::ServerFull) = manager.create().await else {
            panic!()
        };
    }

    #[tokio::test]
    async fn game_cleanup_frees_up_slots() {
        let manager: SessionManager<DummyGame> = SessionManager::new(5);
        for _ in 0..4 {
            let Ok(_) = manager.create().await else {
                panic!()
            };
        }
        let Ok(users) = manager.create().await else {
            panic!()
        };
        let Err(CreateGameError::ServerFull) = manager.create().await else {
            panic!()
        };

        let Ok(_) = manager.destroy_users_game(users[0]).await else {
            panic!()
        };
        let Ok(_) = manager.create().await else {
            panic!()
        };
    }
}
