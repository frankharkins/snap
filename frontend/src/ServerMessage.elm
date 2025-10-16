--- This module is for messages to and from the server
module ServerMessage exposing (ServerMessage(..), decode)

import Json.Decode as JSD

import Game.Events
import Game.Data exposing (PlayerNumber(..), playerNumberToString)

type ServerMessage
  = GameCreated { other_player_id: Int }
  | GameDestroyed
  | ServerFull
  | UserAlreadyConnected
  | GameNotFound
  | GameStarted
  | GameUpdate Game.Events.ServerAction
  | UnknownMessage

decode : String -> ServerMessage
decode wsMsg =
  let _ = (Debug.log "Server message: " wsMsg, ServerFull)
  in case JSD.decodeString serverMessageDecoder wsMsg of
    Ok result -> (Debug.log "Decoded to: " result)
    Err _ -> UnknownMessage

serverMessageDecoder : JSD.Decoder ServerMessage
serverMessageDecoder = JSD.oneOf [
  gameCreatedDecoder
  -- , gameUpdateDecoder
  , unitTypeDecoder
  ]

unitTypeDecoder : JSD.Decoder ServerMessage
unitTypeDecoder = JSD.string |> (
  JSD.map (\s -> case s of
      "ServerFull" -> ServerFull
      "GameDestroyed" -> GameDestroyed
      "UserAlreadyConnected" -> UserAlreadyConnected
      "GameNotFound" -> GameNotFound
      "GameStarted" -> GameStarted
      _ -> UnknownMessage
    )
  )

gameCreatedDecoder : JSD.Decoder ServerMessage
gameCreatedDecoder = JSD.field "GameCreated" (JSD.field "other_player_id" JSD.int)
  |> (JSD.map (\id -> GameCreated { other_player_id = id }))
