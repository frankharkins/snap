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
  , eventLog: List String
  -- We use the following to animate the cards moving between decks
  -- TODO: This is a bit messy as split across here, view, and main
  , centerDeckPosition: (Float, Float)
  , yourDeckOffset: (Float, Float)
  , opponentDeckOffset: (Float, Float)
  }

newTable : Game.Events.PlayerNumber -> Table
newTable playerNumber = {
  yourNumber = playerNumber
  , yourNumCards = 26
  , opponentNumCards = 26
  , centerDeck = []
  , cardDrawnFrom = Nothing
  , lastDrawnTime = 0
  , eventLog = []
  , centerDeckPosition = (0, 0)
  , yourDeckOffset = (0, 0)
  , opponentDeckOffset = (0, 0)
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
  Game.Events.OtherPlayerResponded response -> { table
    | eventLog = table.eventLog ++ [renderUserEvent table response.player response.action response.isMistake]
    }
  _ -> table

updateOffsets : Table -> Player -> (Float, Float) -> Table
updateOffsets table player deckPosition =
  let offset = calculateOffset table.centerDeckPosition deckPosition
  in case player of
    You -> { table | yourDeckOffset = offset }
    Opponent -> { table | opponentDeckOffset = offset }


calculateOffset : (Float, Float) -> (Float, Float) -> (Float, Float)
calculateOffset a b =
  ((Tuple.first b) - (Tuple.first a), (Tuple.second b) - (Tuple.second a))

renderUserEvent : Table -> Game.Events.PlayerNumber -> Game.Events.TimedUserAction -> Bool -> String
renderUserEvent table playerNumber timedAction isMistake =
    let renderedResponseTime = renderResponseTime timedAction.responseTime
        player = playerFromNumber table playerNumber
        playerName = if player == You then "You" else "Opponent"
    in case timedAction.action of
      Game.Events.Draw -> playerName ++ " drew " ++ renderedResponseTime
      Game.Events.Snap -> case isMistake of
        True -> playerName ++ " snapped 🤭"
        False -> playerName ++ " snapped " ++ renderedResponseTime
      Game.Events.NoResponse -> playerName ++ " didn't respond 💀"
      _ -> ""

renderResponseTime : Int -> String
renderResponseTime responseTime =
    "(" ++ (String.fromInt responseTime) ++ "ms " ++ (chooseResponseTimeEmoji responseTime) ++ ")"

chooseResponseTimeEmoji : Int -> String
chooseResponseTimeEmoji responseTime =
        if responseTime < 500 then "🤯"
        else if responseTime < 650 then "🔥"
        else if responseTime < 700 then "🐇"
        else if responseTime < 750 then "🤷"
        else if responseTime < 800 then "🫤"
        else if responseTime < 975 then "🐢"
        else if responseTime < 1500 then "🐌"
        else "🥔"
