module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D

import Game.Data
import Game.Events
import WebSocket
import ServerMessage

main : Program () Model Msg
main =
  Browser.element
    { init = init
    , view = view >> Html.map UserAction
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

type UserAction
  = JoinGameIdChanged String
  | JoinGame
  | CreateGame
  | GameUpdate Game.Events.Action

type Msg
  = UserAction UserAction
  | WebSocketEvent WebSocket.Event

errorState : String -> (Model, Cmd Msg)
errorState message = (ErrorScreen message, Cmd.none)

unexpectedError : (Model, Cmd Msg)
unexpectedError = errorState "An unexpected error occurred"

lostConnectionError : (Model, Cmd Msg)
lostConnectionError = errorState "Lost connection to the server"

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case model of
    InitialScreen state -> case msg of
      WebSocketEvent _ -> (model, Cmd.none)
      UserAction action -> case action of
        JoinGameIdChanged newDraft -> (InitialScreen { draftId = newDraft }, Cmd.none)
        JoinGame -> (Connecting, WebSocket.connect (WebSocket.joinGameUrl state.draftId))
        CreateGame -> (Connecting, WebSocket.connect WebSocket.createGameUrl)
        _ -> (model, Cmd.none)

    Connecting -> case msg of
      UserAction _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionStarted _ -> (Loading, Cmd.none)
        _ -> unexpectedError

    Loading -> case msg of
      UserAction _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.ServerFull -> errorState "The server is full"
          ServerMessage.GameNotFound -> errorState "Couldn't find that game"
          ServerMessage.GameStarted -> (InGame Game.Data.newTable, Cmd.none)
          ServerMessage.GameCreated data -> (WaitingForPlayer { otherPlayerId = String.fromInt data.other_player_id }, Cmd.none)
          _ -> unexpectedError


    WaitingForPlayer info -> case msg of
      UserAction _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.GameStarted -> (InGame Game.Data.newTable, Cmd.none)
          ServerMessage.GameDestroyed -> unexpectedError
          _ -> unexpectedError

    InGame table -> (model, Cmd.none) -- TODO
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

viewInitialScreen : String -> Html UserAction
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

displayMessage : String -> Html UserAction
displayMessage message =
  div [] [ text message ]

view : Model -> Html UserAction
view model =
  case model of
    InitialScreen state -> viewInitialScreen state.draftId
    Connecting -> displayMessage "Connecting"
    Loading -> displayMessage "Loading"
    WaitingForPlayer data -> displayMessage ("Join this game with the code: " ++ data.otherPlayerId)
    ErrorScreen message -> displayMessage message
    _ -> displayMessage "Not implemented yet"
