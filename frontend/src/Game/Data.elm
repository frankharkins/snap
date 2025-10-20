module Game.Data exposing (..)

import Game.Cards exposing (..)
import Game.Events

type Player = You | Opponent

type alias Table = {
  yourNumber: Game.Events.PlayerNumber
  , yourNumCards: Int
  , opponentNumCards: Int
  , centerDeck: List Game.Cards.Card
  , cardDrawnFrom: Maybe Player
  , lastDrawnTime: Int
  }

newTable : Game.Events.PlayerNumber -> Table
newTable playerNumber = {
  yourNumber = playerNumber
  , yourNumCards = 26
  , opponentNumCards = 26
  , centerDeck = []
  , cardDrawnFrom = Nothing
  , lastDrawnTime = 0
  }

playerFromNumber : Table -> Game.Events.PlayerNumber -> Player
playerFromNumber table num = if num == table.yourNumber then You else Opponent

takeCenter : Table -> Game.Events.PlayerNumber -> Table
takeCenter table playerNumber =
  let cardsTaken = List.length table.centerDeck
      tableEmptyCenter = { table | centerDeck = [] }
      player = playerFromNumber table playerNumber
  in
  case player of
    You -> { tableEmptyCenter | yourNumCards = table.yourNumCards + cardsTaken }
    Opponent -> { tableEmptyCenter | opponentNumCards = table.opponentNumCards + cardsTaken }

drawCard : Table -> Game.Events.PlayerNumber -> Game.Cards.Card -> Table
drawCard table playerNumber card =
  let tableNewCenter = { table | centerDeck = table.centerDeck ++ [card] }
      player = playerFromNumber table playerNumber
  in case player of
    You -> { tableNewCenter | yourNumCards = table.yourNumCards - 1, cardDrawnFrom = Just You }
    Opponent -> { tableNewCenter | opponentNumCards = table.opponentNumCards - 1, cardDrawnFrom = Just Opponent }

updateTable : Game.Events.ServerAction -> Table -> Table
updateTable event table = case event of
  Game.Events.CardDrawn drawnEvent -> drawCard table drawnEvent.from drawnEvent.card
  Game.Events.PlayerTakesCenter playerNumber -> takeCenter table playerNumber
  Game.Events.GameRestarted -> newTable table.yourNumber
  _ -> table


topDeckIcon : List Game.Cards.Card -> String
topDeckIcon deck =
  let maybeCard = List.head (List.reverse deck)
  in case maybeCard of
    Nothing -> ""
    Just card -> Game.Cards.toString card
