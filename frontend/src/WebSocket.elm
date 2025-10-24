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


-- This is a bit of a hack: We replace this in the final source with the
-- development / testing URL
-- TODO: Find a better way to do this
baseUrl : String
baseUrl = "929b8e9b3748f2e04edf"

joinGameUrl : String -> String
joinGameUrl id = baseUrl ++ "/join/" ++ id

createGameUrl : String
createGameUrl = baseUrl ++ "/create"
