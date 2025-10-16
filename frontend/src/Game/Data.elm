module Game.Data exposing (..)

import Game.Cards exposing (..)

type PlayerNumber = One | Two

type Player = You | Opponent

playerNumberToString : PlayerNumber -> Maybe PlayerNumber -> String
playerNumberToString num maybeYourNumber =
  case maybeYourNumber of
    Nothing -> case num of
      One -> "Player 1"
      Two -> "Player 2"
    Just yourNumber -> if num == yourNumber then "You" else "Opponent"

playerNumberToPlayer : PlayerNumber -> PlayerNumber -> Player
playerNumberToPlayer player yourNumber =
  if player == yourNumber then You else Opponent


type alias Table = {
  playerOneNumCards: Int
  , playerTwoNumCards: Int
  , centerDeck: List Game.Cards.Card
  , cardDrawnFrom: Maybe PlayerNumber
  }

newTable : Table
newTable = {
  playerOneNumCards = 26
  , playerTwoNumCards = 26
  , centerDeck = []
  , cardDrawnFrom = Nothing
  }

takeCenter : Table -> PlayerNumber -> Table
takeCenter table playerNumber =
  let cardsTaken = List.length table.centerDeck
      tableEmptyCenter = { table | centerDeck = [] }
  in
  case playerNumber of
    One -> { tableEmptyCenter | playerOneNumCards = table.playerOneNumCards + cardsTaken }
    Two -> { tableEmptyCenter | playerTwoNumCards = table.playerTwoNumCards + cardsTaken }

drawCard : Table -> PlayerNumber -> Game.Cards.Card -> Table
drawCard table playerNumber card =
  let tableNewCenter = { table | centerDeck = table.centerDeck ++ [card] }
  in case playerNumber of
    One -> { tableNewCenter | playerOneNumCards = table.playerOneNumCards - 1, cardDrawnFrom = Just One }
    Two -> { tableNewCenter | playerTwoNumCards = table.playerTwoNumCards - 1, cardDrawnFrom = Just Two }

topDeckIcon : List Game.Cards.Card -> String
topDeckIcon deck =
  let maybeCard = List.head (List.reverse deck)
  in case maybeCard of
    Nothing -> ""
    Just card -> Game.Cards.toString card
