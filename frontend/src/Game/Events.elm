module Game.Events exposing (..)
import Game.Data exposing (PlayerNumber)
import Game.Cards exposing (Card)

-- Possible actions a user can make
type Action
  = Draw
  | Snap
  | NoResponse
  | PlayAgain


type alias TimedUserAction = {
    action: Action
    , responseTime: Int
    }

type ServerAction
  = YourNumber PlayerNumber
  | CardDrawn { from: PlayerNumber, card: Card }
  | OtherPlayerResponded { action: TimedUserAction, isMistake: Bool }
  | PlayerTakesCenter PlayerNumber
  | PlayerWins PlayerNumber
  | GameRestarted
  | SomethingWentWrong

-- TODO: Maybe encode rather than string interpolation? Maybe not necessary
actionToJson : Action -> Int -> String
actionToJson action responseTime =
  case action of
    Draw -> "{\"Draw\":" ++ String.fromInt responseTime ++ "}"
    Snap -> "{\"Snap\":" ++ String.fromInt responseTime ++ "}"
    NoResponse -> "{\"NoResponse\":null}"
    PlayAgain -> "{\"PlayAgain\":null}"



renderUserAction : TimedUserAction -> Bool -> String
renderUserAction timedAction isMistake =
    let renderedResponseTime = renderResponseTime timedAction.responseTime
    in case timedAction.action of
      Draw -> "Draw " ++ renderedResponseTime
      Snap -> case isMistake of
        True -> "Snap 🤭"
        False -> "Snap " ++ renderedResponseTime
      NoResponse -> "No response 💀"
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
