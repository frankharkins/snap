--- This module is for messages to and from the server
module ServerMessage exposing (ServerMessage(..), decode)

import Json.Decode as JSD

import Game.Events

type ServerMessage
  = GameCreated { other_player_id: Int }
  | GameDestroyed
  | ServerFull
  | UserAlreadyConnected
  | GameNotFound
  | GameStarted { yourNumber: Game.Events.PlayerNumber }
  | GameUpdate Game.Events.ServerAction
  | UnknownMessage

decode : String -> ServerMessage
decode wsMsg =
  let _ = (wsMsg, ServerFull)
  in case JSD.decodeString serverMessageDecoder wsMsg of
    Ok result -> result
    Err _ -> UnknownMessage

serverMessageDecoder : JSD.Decoder ServerMessage
serverMessageDecoder = JSD.oneOf [
  gameCreatedDecoder
  , gameStartedDecoder
  , gameUpdateDecoder
  , unitTypeDecoder
  ]

unitTypeDecoder : JSD.Decoder ServerMessage
unitTypeDecoder = JSD.string |> (
  JSD.map (\s -> case s of
      "ServerFull" -> ServerFull
      "GameDestroyed" -> GameDestroyed
      "UserAlreadyConnected" -> UserAlreadyConnected
      "GameNotFound" -> GameNotFound
      _ -> UnknownMessage
    )
  )

gameCreatedDecoder : JSD.Decoder ServerMessage
gameCreatedDecoder = JSD.field "GameCreated" (JSD.field "other_player_id" JSD.int)
  |> (JSD.map (\id -> GameCreated { other_player_id = id }))


gameStartedDecoder : JSD.Decoder ServerMessage
gameStartedDecoder = JSD.field "GameStarted" (JSD.field "your_number" Game.Events.playerNumberDecoder)
  |> (JSD.map (\num -> GameStarted { yourNumber = num }))

gameUpdateDecoder : JSD.Decoder ServerMessage
gameUpdateDecoder = JSD.field "GameUpdate" Game.Events.updateDecoder |> JSD.map GameUpdate
