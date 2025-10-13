mod game;
mod manager;
mod message;

const MAX_NUM_GAMES: usize = 3;

fn main() {
    let session_manager = manager::SessionManager::<game::Snap>::new(MAX_NUM_GAMES);
}
