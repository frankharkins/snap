port module WebSocket exposing (..)

port connect : String -> Cmd msg
port sendMessage : String -> Cmd msg
port messageReceived : (String -> msg) -> Sub msg
port connectionLost : (() -> msg) -> Sub msg
port connectionStarted : (() -> msg) -> Sub msg

type Event =
  ConnectionStarted ()
  | ConnectionLost ()
  | MessageReceived String

baseUrl : String
baseUrl = "ws://localhost:3030"

joinGameUrl : String -> String
joinGameUrl id = baseUrl ++ "/join/" ++ id

createGameUrl : String
createGameUrl = baseUrl ++ "/create"
