module Game.Cards exposing (Card, Suit, Value, toString, cardFace, cardDecoder)

import Json.Decode as JSD

-- Types for cards
type Suit
  = Clubs
  | Hearts
  | Diamonds
  | Spades

type Value
  = Two
  | Three
  | Four
  | Five
  | Six
  | Seven
  | Eight
  | Nine
  | Ten
  | Jack
  | Queen
  | King
  | Ace

type alias Card = { suit: Suit, value: Value }

suitToString : Suit -> String
suitToString suit =
  case suit of
    Clubs -> "Clubs"
    Hearts -> "Hearts"
    Diamonds -> "Diamonds"
    Spades -> "Spades"

valueToString : Value -> String
valueToString value =
  case value of
    Two -> "Two"
    Three -> "Three"
    Four -> "Four"
    Five -> "Five"
    Six -> "Six"
    Seven -> "Seven"
    Eight -> "Eight"
    Nine -> "Nine"
    Ten -> "Ten"
    Jack -> "Jack"
    Queen -> "Queen"
    King -> "King"
    Ace -> "Ace"

toString : Card -> String
toString card =
  (valueToString card.value) ++ " of " ++ (suitToString card.suit)

suitDecoder : JSD.Decoder Suit
suitDecoder =
    JSD.string
        |> JSD.andThen
            (\s ->
                case s of
                    "Hearts" -> JSD.succeed Hearts
                    "Diamonds" -> JSD.succeed Diamonds
                    "Clubs" -> JSD.succeed Clubs
                    "Spades" -> JSD.succeed Spades
                    _ -> JSD.fail ("Unknown suit: " ++ s)
            )

valueDecoder : JSD.Decoder Value
valueDecoder =
    JSD.string
        |> JSD.andThen
            (\v ->
                case v of
                    "Two" -> JSD.succeed Two
                    "Three" -> JSD.succeed Three
                    "Four" -> JSD.succeed Four
                    "Five" -> JSD.succeed Five
                    "Six" -> JSD.succeed Six
                    "Seven" -> JSD.succeed Seven
                    "Eight" -> JSD.succeed Eight
                    "Nine" -> JSD.succeed Nine
                    "Ten" -> JSD.succeed Ten
                    "Jack" -> JSD.succeed Jack
                    "Queen" -> JSD.succeed Queen
                    "King" -> JSD.succeed King
                    "Ace" -> JSD.succeed Ace
                    _ -> JSD.fail ("Unknown value: " ++ v)
            )

cardDecoder : JSD.Decoder Card
cardDecoder =
  JSD.map2 Card
    (JSD.field "suit" suitDecoder)
    (JSD.field "value" valueDecoder)

cardFace : Card -> String
cardFace card =
  let
    value = case card.value of
      Two -> "2"
      Three -> "3"
      Four -> "4"
      Five -> "5"
      Six -> "6"
      Seven -> "7"
      Eight -> "8"
      Nine -> "9"
      Ten -> "10"
      Jack -> "J"
      Queen -> "Q"
      King -> "K"
      Ace -> "A"
    suit = case card.suit of
      Clubs -> "clubs"
      Hearts -> "hearts"
      Diamonds -> "diamonds"
      Spades -> "spades"
  in
    "url(\"/images/faces/" ++ value ++ "-" ++ suit ++ ".png\")"
