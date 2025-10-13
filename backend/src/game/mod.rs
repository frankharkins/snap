use serde::{Deserialize, Serialize};

mod cards;
use crate::manager;
use crate::message;

/// Milliseconds taken for user to respond, measured by their browser
type ResponseTimeMs = u32;

/// Player's position at the table
type PlayerNumber = usize;

/// In case I want to generalize later
const NUM_PLAYERS: usize = 2;

/// The allowed in-game messages from the client
#[derive(Copy, Clone, Debug, Deserialize, Serialize)]
pub enum InputMessageType {
    /// User drew a card
    Draw(ResponseTimeMs),
    /// User snapped a card
    Snap(ResponseTimeMs),
    /// User did not respond in time
    NoResponse,
    /// User wants to play again
    PlayAgain,
}

impl InputMessageType {
    pub fn was_faster_than(&self, other: &Self) -> bool {
        match self {
            Self::NoResponse | Self::PlayAgain => false,
            Self::Draw(time) | Self::Snap(time) => match other {
                Self::NoResponse | Self::PlayAgain => true,
                Self::Draw(other_time) => time < other_time,
                Self::Snap(other_time) => time < other_time,
            },
        }
    }
}

type InputMessage = message::InputMessage<PlayerNumber, InputMessageType>;

#[derive(Copy, Clone, Deserialize, Serialize)]
pub enum OutputMessageType {
    YourNumber(PlayerNumber),
    CardDrawn {
        card: cards::Card,
        from: PlayerNumber,
    },
    OtherPlayerResponded {
        player: PlayerNumber,
        msg: InputMessageType,
        is_mistake: bool,
    },
    PlayerTakesCenter(PlayerNumber),
    PlayerWins(PlayerNumber),
    SomethingWentWrong,
    // usize is redundant, I just can't work out how to get an empty enum
    // variant to serialize to "{\"GameRestarted\":null}" rather than just
    // "GameRestarted"
    GameRestarted(usize),
}

type OutputMessage = message::OutputMessage<PlayerNumber, OutputMessageType>;

struct Player {
    hand: cards::CardPile,
    pending_message: Option<InputMessageType>,
}

pub struct Snap {
    players: [Player; NUM_PLAYERS],
    player_turn: PlayerNumber,
    center_pile: cards::CardPile,
}

impl Default for Snap {
    fn default() -> Self {
        let (hand1, hand2) = cards::deal_deck();
        let players = [
            Player {
                hand: hand1,
                pending_message: None,
            },
            Player {
                hand: hand2,
                pending_message: None,
            },
        ];
        Self {
            players,
            player_turn: 0,
            center_pile: cards::CardPile::new(),
        }
    }
}

impl Snap {
    // Game entered an unexpected state, abort, log, and notify players
    fn abort(&mut self, _reason: &str) -> Vec<OutputMessage> {
        println!("Something went wrong");
        self.to_all_players(OutputMessageType::SomethingWentWrong)
    }

    fn clear_pending_messages(&mut self) {
        for player in (0..NUM_PLAYERS) {
            self.players[player].pending_message = None;
        }
    }

    fn snap_possible(&self) -> bool {
        match (self.center_pile.last(), self.center_pile.penultimate()) {
            (Some(last), Some(penultimate)) => last.value == penultimate.value,
            _ => false,
        }
    }

    /// Game ends when a player gets rid of all their cards
    fn has_ended(&self) -> bool {
        (!self.snap_possible()) && self.players.iter().any(|p| p.hand.is_empty())
    }

    fn to_all_players(&self, message: OutputMessageType) -> Vec<OutputMessage> {
        (0..NUM_PLAYERS)
            .map(|player| message::OutputMessage {
                recipient: player,
                message,
            })
            .collect()
    }

    /// Draw a card, notify players, and bump the turn counter.
    /// Also declare a winner if this draw ends the game.
    fn draw_card(&mut self) -> Vec<OutputMessage> {
        let player_hand = &mut self.players[self.player_turn].hand;
        let card = match player_hand.draw() {
            None => return self.abort("Draw from empty hand"),
            Some(card) => card,
        };

        // Alert each player a card has been drawn
        let mut messages: Vec<OutputMessage> = self.to_all_players(OutputMessageType::CardDrawn {
            card,
            from: self.player_turn,
        });

        // Add card to center pile
        self.center_pile.place(card);

        // If the game has ended, declare the current player the winner
        if self.has_ended() {
            messages.extend(self.to_all_players(OutputMessageType::PlayerWins(self.player_turn)));
        } else {
            self.player_turn = (self.player_turn + 1) % NUM_PLAYERS;
        }
        return messages;
    }

    fn player_takes_center(&mut self, player: PlayerNumber) -> Vec<OutputMessage> {
        self.players[player].hand.absorb(&mut self.center_pile);
        self.players[player].hand.shuffle();
        self.player_turn = player;
        self.to_all_players(OutputMessageType::PlayerTakesCenter(player))
    }
}

impl manager::Game for Snap {
    type InputMessage = InputMessageType;
    type OutputMessage = OutputMessageType;
    const NUM_PLAYERS: usize = 2;

    /// Advance the game and return any messages to be passed to users
    fn player_action(&mut self, message: InputMessage) -> Vec<OutputMessage> {
        if self.has_ended() {
            return match message.message {
                InputMessageType::PlayAgain => {
                    *self = Snap::default();
                    self.to_all_players(OutputMessageType::GameRestarted(0))
                }
                _ => log_invalid(message, "Game ended"),
            };
        }

        // Player can only send "Draw" if it's their turn
        match message.message {
            InputMessageType::Draw(_) => {
                if message.sender != self.player_turn {
                    return log_invalid(message, "Not this player's turn");
                }
            }
            _ => {}
        }

        if !self.snap_possible() {
            // If a snap isn't possible, the only valid message is a "draw" from
            // the current player, and we've already checked all draws are from
            // the current player.
            return match message.message {
                // We've already checked
                InputMessageType::Draw(_) => self.draw_card(),
                InputMessageType::Snap(_) => {
                    // Player has made an incorrect snap; they take the center
                    let mut messages =
                        self.to_all_players(OutputMessageType::OtherPlayerResponded {
                            player: message.sender,
                            msg: message.message,
                            is_mistake: true,
                        });
                    messages.extend(self.player_takes_center(message.sender));
                    messages
                }
                _ => log_invalid(
                    message,
                    "Only valid message is \"draw\" from current player",
                ),
            };
        }

        // Snap is possible: We need to wait for everyone's response before
        // continuing.
        //
        // First, store player's message and notify all other players.
        if !self.players[message.sender].pending_message.is_none() {
            return vec![];
        }
        self.players[message.sender].pending_message = Some(message.message);
        let mut server_msgs: Vec<OutputMessage> =
            self.to_all_players(OutputMessageType::OtherPlayerResponded {
                player: message.sender,
                msg: message.message,
                is_mistake: false,
            });

        // If any player is still to respond, we continue waiting.
        let maybe_all_responses: Option<Vec<_>> =
            self.players.iter().map(|p| p.pending_message).collect();
        match maybe_all_responses {
            // Still waiting for someone to reply
            None => return server_msgs,

            // Everyone has replied: Decide how to proceed
            Some(mut all_responses) => {
                let (fastest_player, fastest_response) =
                    match get_fastest_response(&mut all_responses) {
                        None => return self.abort("Could not determine winning response"),
                        Some((player, response)) => (player, response),
                    };

                self.clear_pending_messages();
                match fastest_response {
                    InputMessageType::NoResponse | InputMessageType::PlayAgain => {
                        return self.abort("Unexpected fastest response type");
                    }
                    InputMessageType::Draw(_) => {
                        server_msgs.extend(self.draw_card());
                        server_msgs
                    }
                    InputMessageType::Snap(_) => {
                        let loser = (fastest_player + 1) % 2;
                        server_msgs.extend(self.player_takes_center(loser));
                        server_msgs
                    }
                }
            }
        }
    }
}

/// This message is not valid for this game state; log and return no messages to clients.
fn log_invalid(message: InputMessage, reason: &str) -> Vec<OutputMessage> {
    println!(
        "Unexpected message \"{:?}\" from player {}; {}",
        message.message, message.sender, reason
    );
    return vec![];
}

fn get_fastest_response(
    messages: &mut Vec<InputMessageType>,
) -> Option<(PlayerNumber, &InputMessageType)> {
    messages
        .iter()
        .enumerate()
        .reduce(|(winner, winner_msg), (player, msg)| {
            if msg.was_faster_than(winner_msg) {
                (player, msg)
            } else {
                (winner, winner_msg)
            }
        })
}
