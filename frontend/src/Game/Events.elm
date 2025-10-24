module Game.Events exposing (..)
import Game.Cards

import Json.Decode as JSD

type PlayerNumber = One | Two

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
  = CardDrawn { from: PlayerNumber, card: Game.Cards.Card }
  | InvalidDraw
  | OtherPlayerResponded { player: PlayerNumber, action: TimedUserAction, isMistake: Bool }
  | PlayerTakesCenter PlayerNumber
  | PlayerWins PlayerNumber
  | GameRestarted
  | SomethingWentWrong

-- TODO: Maybe encode rather than string interpolation? Maybe not necessary
actionToJson : Action -> Int -> String
actionToJson action responseTime =
  case action of
    Draw -> "{\"GameUpdate\":{\"Draw\":" ++ String.fromInt responseTime ++ "}}"
    Snap -> "{\"GameUpdate\":{\"Snap\":" ++ String.fromInt responseTime ++ "}}"
    NoResponse -> "{\"GameUpdate\":{\"NoResponse\":null}}"
    PlayAgain -> "{\"GameUpdate\":{\"PlayAgain\":null}}"



updateDecoder : JSD.Decoder ServerAction
updateDecoder = JSD.oneOf [
  JSD.field "CardDrawn" (cardDrawnDecoder)
  , JSD.field "OtherPlayerResponded" (otherPlayerRespondedDecoder)
  , JSD.field "PlayerTakesCenter" (playerEventDecoder PlayerTakesCenter)
  , JSD.field "PlayerWins" (playerEventDecoder PlayerWins)
  , unitTypeDecoder
  ]

playerEventDecoder : (PlayerNumber -> b) -> JSD.Decoder b
playerEventDecoder eventType = JSD.map (\player -> eventType player) playerNumberDecoder

otherPlayerRespondedDecoder :  JSD.Decoder ServerAction
otherPlayerRespondedDecoder = JSD.map3
  (\player -> \timedAction -> \isMistake -> OtherPlayerResponded { player = player, action = timedAction, isMistake = isMistake })
  (JSD.field "player" playerNumberDecoder)
  (JSD.field "msg" timedActionDecoder)
  (JSD.field "is_mistake" JSD.bool)

timedActionDecoder : JSD.Decoder TimedUserAction
timedActionDecoder = JSD.oneOf [
  JSD.map (\time -> { responseTime = time, action = Draw }) (JSD.field "Draw" JSD.int)
  , JSD.map (\time -> { responseTime = time, action = Snap }) (JSD.field "Snap" JSD.int)
  , JSD.map (\time -> { responseTime = time, action = NoResponse }) (JSD.field "NoResponse" JSD.int)
  , JSD.map (\time -> { responseTime = time, action = PlayAgain }) (JSD.field "PlayAgain" JSD.int)
  ]


cardDrawnDecoder : JSD.Decoder ServerAction
cardDrawnDecoder = JSD.map2
  (\player -> \card -> CardDrawn { from = player, card = card })
  (JSD.field "from" playerNumberDecoder)
  (JSD.field "card" Game.Cards.cardDecoder)

playerNumberDecoder : JSD.Decoder PlayerNumber
playerNumberDecoder = JSD.int |> JSD.andThen (
  \i -> case i of
    0 -> JSD.succeed One
    1 -> JSD.succeed Two
    _ -> JSD.fail "Unexpected player number"
  )

unitTypeDecoder : JSD.Decoder ServerAction
unitTypeDecoder = JSD.string |> (
  JSD.map (\s -> case s of
      "GameRestarted" -> GameRestarted
      "InvalidDraw" -> InvalidDraw
      "SomethingWentWrong" -> SomethingWentWrong
      _ -> SomethingWentWrong
    )
  )
