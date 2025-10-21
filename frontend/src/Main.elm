module Main exposing (..)

import Browser
import Browser.Dom as Dom
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Time

import Game.Data
import Game.Events
import Game.View
import WebSocket
import ServerMessage
import Task
import Platform.Cmd as Cmd

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
  | SubmitGameEvent Game.Events.Action Time.Posix
  | GotElement String (Result Dom.Error Dom.Element)

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

getDeckPosition : Game.View.Deck -> Cmd Msg
getDeckPosition deck = let id = Game.View.deckToId deck in
  Task.attempt (\r -> ClientEvent (GotElement id r)) (Dom.getElement id)

onStartGame : Cmd Msg
onStartGame = Cmd.batch [ updateLastDrawnTime, getDeckPosition Game.View.Center ]


-- To submit a game action, we need to get the current time
submitGameEvent : Game.Events.Action -> Cmd Msg
submitGameEvent action = Task.perform (\t -> ClientEvent (SubmitGameEvent action t)) Time.now

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
          ServerMessage.GameStarted data -> (InGame (Game.Data.newTable data.yourNumber), onStartGame)
          ServerMessage.GameCreated data -> (WaitingForPlayer { otherPlayerId = String.fromInt data.other_player_id }, Cmd.none)
          _ -> unexpectedError


    WaitingForPlayer info -> case msg of
      ClientEvent _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.GameStarted data -> (InGame (Game.Data.newTable data.yourNumber), onStartGame)
          ServerMessage.GameDestroyed -> unexpectedError
          _ -> unexpectedError

    InGame table -> case msg of
      WebSocketEvent event -> case event of
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.GameDestroyed -> errorState "The game was destroyed"
          ServerMessage.GameUpdate gameEvent -> let newModel = InGame (Game.Data.updateTable gameEvent table)
            in case gameEvent of
              Game.Events.SomethingWentWrong -> unexpectedError
              Game.Events.CardDrawn _ -> (newModel, updateLastDrawnTime)
              Game.Events.PlayerTakesCenter _ -> (newModel, updateLastDrawnTime)
              Game.Events.GameRestarted -> (newModel, onStartGame)
              Game.Events.OtherPlayerResponded response -> (newModel, Cmd.none)
              _ -> (newModel, Cmd.none)
          _ -> unexpectedError
      ClientEvent event -> case event of
        SetLastDrawTime time -> (
          InGame { table | lastDrawnTime = Time.posixToMillis (Debug.log "time: " time) }
          , Cmd.none
          )
        GameAction action -> (model, submitGameEvent action) -- TODO: Update model too
        SubmitGameEvent gameEvent currentTime -> let responseTime = (Time.posixToMillis currentTime) - table.lastDrawnTime
          in (model, WebSocket.sendMessage (Game.Events.actionToJson gameEvent responseTime))
        GotElement id result -> case (Game.View.idToDeck id) of
          Nothing -> unexpectedError
          Just deck -> case result of
            Err _ -> unexpectedError
            Ok element -> let position = (element.element.x, element.element.y) in case deck of
              Game.View.Center -> (
                InGame { table | centerDeckPosition = position }
                , Cmd.batch [ getDeckPosition Game.View.Yours, getDeckPosition Game.View.Opponents ]
                )
              Game.View.Yours -> (InGame (Game.Data.updateOffsets table Game.Data.You position), Cmd.none)
              Game.View.Opponents -> (InGame (Game.Data.updateOffsets table Game.Data.Opponent position), Cmd.none)
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

appContainer : Html ClientEvent -> Html ClientEvent
appContainer contents =
  div [ class "fullscreen" ] [
    div [ class "app" ] ([
      header [] [ h1 [] [ text "Snap!" ] ]
      , contents
    ])
  ]

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

view : Model -> Html ClientEvent
view model = appContainer (
  case model of
    InitialScreen state -> viewInitialScreen state.draftId
    Connecting -> displayMessage "Connecting"
    Loading -> displayMessage "Loading"
    WaitingForPlayer data -> displayMessage ("Join this game with the code: " ++ data.otherPlayerId)
    ErrorScreen message -> displayMessage message
    InGame table -> (Game.View.viewTable table) |> Html.map GameAction
    _ -> displayMessage "Not implemented yet"
  )
