use itertools::iproduct;
use rand::seq::SliceRandom;
use serde::{Deserialize, Serialize};

#[derive(Copy, Clone, Debug, Serialize, Deserialize)]
pub enum Suit {
    Clubs,
    Hearts,
    Spades,
    Diamonds,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Value {
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight,
    Nine,
    Ten,
    Jack,
    Queen,
    King,
    Ace,
}

#[derive(Copy, Clone, Debug, Serialize, Deserialize)]
pub struct Card {
    pub suit: Suit,
    pub value: Value,
}

impl Card {
    pub fn to_string(&self) -> String {
        let mut name = match self.value {
            Value::Two => "2",
            Value::Three => "3",
            Value::Four => "4",
            Value::Five => "5",
            Value::Six => "6",
            Value::Seven => "7",
            Value::Eight => "8",
            Value::Nine => "9",
            Value::Ten => "10",
            Value::Jack => "J",
            Value::Queen => "Q",
            Value::King => "K",
            Value::Ace => "A",
        }
        .to_owned();
        name.push_str(match self.suit {
            Suit::Clubs => "♣",
            Suit::Hearts => "♥",
            Suit::Diamonds => "♦",
            Suit::Spades => "♠",
        });
        return name;
    }
}

pub struct CardPile(Vec<Card>);

impl CardPile {
    pub fn new() -> Self {
        CardPile(Vec::with_capacity(52))
    }
    pub fn shuffle(&mut self) {
        let mut rng = rand::rng();
        self.0.shuffle(&mut rng);
    }

    pub fn is_empty(&self) -> bool {
        self.0.len() == 0
    }

    pub fn last(&self) -> Option<&Card> {
        self.0.last()
    }

    pub fn penultimate(&self) -> Option<&Card> {
        if self.0.len() < 2 {
            return None;
        };
        return Some(&self.0[self.0.len() - 2]);
    }

    pub fn draw(&mut self) -> Option<Card> {
        self.0.pop()
    }

    pub fn place(&mut self, card: Card) {
        self.0.push(card)
    }

    /// Move all the cards from another pile, leaving the other empty
    pub fn absorb(&mut self, other: &mut Self) {
        while let Some(card) = other.draw() {
            self.place(card);
        }
    }
}

fn new_deck() -> CardPile {
    let suits: Vec<Suit> = vec![Suit::Clubs, Suit::Hearts, Suit::Spades, Suit::Diamonds];

    let values: Vec<Value> = vec![
        Value::Two,
        Value::Three,
        Value::Four,
        Value::Five,
        Value::Six,
        Value::Seven,
        Value::Eight,
        Value::Nine,
        Value::Ten,
        Value::Jack,
        Value::Queen,
        Value::King,
        Value::Ace,
    ];

    let cards = iproduct!(suits.iter(), values.iter())
        .map(|(&suit, &value)| Card { suit, value })
        .collect();

    CardPile(cards)
}

/// Deal a shuffled deck into two piles
pub fn deal_deck() -> (CardPile, CardPile) {
    let mut deck = new_deck();
    deck.shuffle();

    let mut left = CardPile::new();
    let mut right = CardPile::new();

    left.0.extend_from_slice(&deck.0[0..26]);
    right.0.extend_from_slice(&deck.0[26..52]);

    return (left, right);
}
