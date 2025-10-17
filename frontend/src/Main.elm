module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Time

import Game.Data
import Game.Events
import WebSocket
import ServerMessage
import Task

main : Program () Model Msg
main =
  Browser.element
    { init = init
    , view = view >> Html.map ClientEvent
    , update = update
    , subscriptions = subscriptions
    }

type Model
  = InitialScreen { draftId: String }
  | WaitingForPlayer { otherPlayerId: String }
  | Connecting
  | Loading
  | InGame Game.Data.Table
  | EndGame { winner: Game.Data.Player, playAgain: Bool }
  | ErrorScreen String


init : () -> ( Model, Cmd Msg )
init _ = (
  InitialScreen { draftId = "" }
  , Cmd.none
  )

type ClientEvent
  -- Events triggered by user interaction
  = JoinGameIdChanged String
  | JoinGame
  | CreateGame
  | GameAction Game.Events.Action
  -- Events triggered automatically
  | SetLastDrawTime Time.Posix

type Msg
  = ClientEvent ClientEvent
  | WebSocketEvent WebSocket.Event

errorState : String -> (Model, Cmd Msg)
errorState message = (ErrorScreen message, Cmd.none)

unexpectedError : (Model, Cmd Msg)
unexpectedError = errorState "An unexpected error occurred"

lostConnectionError : (Model, Cmd Msg)
lostConnectionError = errorState "Lost connection to the server"

updateLastDrawnTime : Cmd Msg
updateLastDrawnTime = Task.perform (\t -> ClientEvent (SetLastDrawTime t)) Time.now

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case model of
    InitialScreen state -> case msg of
      WebSocketEvent _ -> (model, Cmd.none)
      ClientEvent event -> case event of
        JoinGameIdChanged newDraft -> (InitialScreen { draftId = newDraft }, Cmd.none)
        JoinGame -> (Connecting, WebSocket.connect (WebSocket.joinGameUrl state.draftId))
        CreateGame -> (Connecting, WebSocket.connect WebSocket.createGameUrl)
        _ -> (model, Cmd.none)

    Connecting -> case msg of
      ClientEvent _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionStarted _ -> (Loading, Cmd.none)
        _ -> unexpectedError

    Loading -> case msg of
      ClientEvent _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.ServerFull -> errorState "The server is full"
          ServerMessage.GameNotFound -> errorState "Couldn't find that game"
          ServerMessage.GameStarted -> (InGame Game.Data.newTable, updateLastDrawnTime)
          ServerMessage.GameCreated data -> (WaitingForPlayer { otherPlayerId = String.fromInt data.other_player_id }, Cmd.none)
          _ -> unexpectedError


    WaitingForPlayer info -> case msg of
      ClientEvent _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.GameStarted -> (InGame Game.Data.newTable, updateLastDrawnTime)
          ServerMessage.GameDestroyed -> unexpectedError
          _ -> unexpectedError

    InGame table -> case msg of
      WebSocketEvent event -> case event of
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.GameDestroyed -> errorState "The game was destroyed"
          ServerMessage.GameUpdate gameEvent -> case gameEvent of
            Game.Events.CardDrawn cardEvent -> (model, updateLastDrawnTime) --TODO
            _ -> (model, Cmd.none) -- TODO
          _ -> unexpectedError
      ClientEvent event -> case event of
        SetLastDrawTime time -> (
          InGame { table | lastDrawnTime = Time.posixToMillis (Debug.log "time: " time) }
          , Cmd.none
          )
        GameAction action -> case action of
          -- TODO: We're sending last drawn time when we should be sending difference between that and now
          Game.Events.Draw -> (model, WebSocket.sendMessage ("{\"GameUpdate\":{\"Draw\":" ++ String.fromInt (table.lastDrawnTime) ++ "}}"))
          Game.Events.Snap -> (model, WebSocket.sendMessage ("{\"GameUpdate\":{\"Snap\":" ++ String.fromInt (table.lastDrawnTime) ++ "}}"))
          Game.Events.NoResponse -> (model, Cmd.none)
          Game.Events.PlayAgain -> (model, Cmd.none)
        _ -> (model, Cmd.none)

    EndGame info -> (model, Cmd.none) -- TODO
    ErrorScreen _ -> (model, Cmd.none)


-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.batch [
  WebSocket.messageReceived (\m -> WebSocketEvent (WebSocket.MessageReceived m))
  , WebSocket.connectionLost (\_ -> WebSocketEvent (WebSocket.ConnectionLost ()))
  , WebSocket.connectionStarted (\_ -> WebSocketEvent (WebSocket.ConnectionStarted ()))
  ]


-- VIEW

viewInitialScreen : String -> Html ClientEvent
viewInitialScreen draftId =
  div []
    [
       input
        [ type_ "text"
        , placeholder "Game ID"
        , onInput JoinGameIdChanged
        , value draftId
        ]
        []
      , button [ onClick JoinGame ] [ text "Join" ]
      , button [ onClick CreateGame ] [ text "Create" ]
    ]

displayMessage : String -> Html ClientEvent
displayMessage message =
  div [] [ text message ]

viewGame : Game.Data.Table -> Html Game.Events.Action
viewGame table =
  div [] [
    button [ onClick Game.Events.Draw ] [ text "Draw" ]
    , button [ onClick Game.Events.Snap ] [ text "Snap" ]
    ]

view : Model -> Html ClientEvent
view model =
  case model of
    InitialScreen state -> viewInitialScreen state.draftId
    Connecting -> displayMessage "Connecting"
    Loading -> displayMessage "Loading"
    WaitingForPlayer data -> displayMessage ("Join this game with the code: " ++ data.otherPlayerId)
    ErrorScreen message -> displayMessage message
    InGame table -> (viewGame table) |> Html.map GameAction
    _ -> displayMessage "Not implemented yet"
