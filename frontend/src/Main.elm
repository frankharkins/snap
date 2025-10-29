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
  | EndGame Game.Data.Table { winner: Game.Data.Player, playAgainPressed: Bool, yourNumber: Game.Events.PlayerNumber }
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
  | DismissError
  -- Events triggered automatically
  | SetLastDrawTime Time.Posix
  | SubmitGameEvent Game.Events.Action Time.Posix
  | GotElement String (Result Dom.Error Dom.Element)
  | NoOp

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
        WebSocket.ConnectionLost _ -> errorState "Can't connect to the server"
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
              Game.Events.InvalidDraw -> (newModel, updateLastDrawnTime)
              Game.Events.PlayerTakesCenter _ -> (newModel, updateLastDrawnTime)
              Game.Events.GameRestarted -> (newModel, onStartGame)
              Game.Events.OtherPlayerResponded response -> (newModel, Cmd.none)
              Game.Events.PlayerWins playerNumber -> (
                EndGame table {
                  winner = Game.Data.playerFromNumber table playerNumber
                  , playAgainPressed = False
                  , yourNumber = table.yourNumber
                  }
                , Cmd.none
                )
          _ -> unexpectedError
      ClientEvent event -> case event of
        SetLastDrawTime time -> (
          InGame { table | lastDrawnTime = Time.posixToMillis time }
          , Cmd.none
          )
        GameAction action -> (model, submitGameEvent action)
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

    EndGame table info -> case msg of
      ClientEvent event -> case event of
        SubmitGameEvent gameEvent _ -> (model, WebSocket.sendMessage (Game.Events.actionToJson gameEvent 0))
        GameAction action -> case action of
          Game.Events.PlayAgain -> (EndGame table { info | playAgainPressed = True }, submitGameEvent action)
          _ -> (model, Cmd.none)
        _ -> (model, Cmd.none)
      WebSocketEvent event -> case event of
        WebSocket.ConnectionLost _ -> lostConnectionError
        WebSocket.ConnectionStarted _ -> unexpectedError
        WebSocket.MessageReceived wsMsg -> case (ServerMessage.decode wsMsg) of
          ServerMessage.GameDestroyed -> errorState "The game was destroyed"
          ServerMessage.GameUpdate gameEvent -> case gameEvent of
              Game.Events.GameRestarted -> (InGame (Game.Data.newTable info.yourNumber), onStartGame)
              _ -> unexpectedError
          _ -> unexpectedError

    ErrorScreen _ -> case msg of
        ClientEvent event -> case event of
            DismissError -> init ()
            _ -> (model, Cmd.none)
        _ -> (model, Cmd.none)


-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.batch [
  WebSocket.messageReceived (\m -> WebSocketEvent (WebSocket.MessageReceived m))
  , WebSocket.connectionLost (\_ -> WebSocketEvent (WebSocket.ConnectionLost ()))
  , WebSocket.connectionStarted (\_ -> WebSocketEvent (WebSocket.ConnectionStarted ()))
  ]


-- VIEW

appContainer : List (Html ClientEvent) -> Html ClientEvent
appContainer contents =
  div [ class "fullscreen" ] [
    div [ class "app" ] ([
      header [] [
        h1 [] [ text "Snap!" ]
        , span [ class "author" ] [
          text "by"
          , text " "
          , a [ href "https://frankharkins.github.io" ] [ text "Frank Harkins" ]
        ]
      ]
    ] ++ contents)
  ]

viewInitialScreen : String -> Html ClientEvent
viewInitialScreen draftId =
  div [ class "non-game-container" ]
    [
       div [ class "join-game" ] [
         input
          [ type_ "text"
          , placeholder "Game ID"
          , onInput JoinGameIdChanged
          , value draftId
          ]
          []
         , button [ onClick JoinGame ] [ text "Join" ]
        ]
      , div [] [ text "or" ]
      , button [ onClick CreateGame ] [ text "Start a new game" ]
    ]

displayMessage : List String -> Html ClientEvent
displayMessage message =
  div [ class "non-game-container" ] (
    message |> List.map (\t -> p [] [ text t ])
  )


displayError : String -> Html ClientEvent
displayError message =
  div [ class "non-game-container" ] [
    text ("Error: " ++ message)
    , button [ onClick DismissError ] [ text "Ok" ]
    ]



endGame : Game.Data.Table -> Game.Data.Player -> Bool -> List (Html ClientEvent)
endGame table winner playAgainPressed =
  let
    message = case winner of
      Game.Data.You -> "You win! 🎉"
      Game.Data.Opponent -> "Opponent wins"
  in [
    (Game.View.viewTable table) |> Html.map (\_ -> NoOp)
    , div [ class "modal" ] [
      text message
      , button [ disabled playAgainPressed, onClick (GameAction Game.Events.PlayAgain) ] [ text "Play again" ]
      ]
    ]


view : Model -> Html ClientEvent
view model = appContainer (
  case model of
    InitialScreen state -> [ viewInitialScreen state.draftId ]
    Connecting -> [ displayMessage [ "Connecting...", "(This can sometimes take a minute as the service spins down when inactive)" ] ]
    Loading -> [ displayMessage [ "Loading" ] ]
    WaitingForPlayer data -> [ displayMessage [ "Tell a friend to join using the following code: " ++ data.otherPlayerId ] ]
    ErrorScreen message -> [ displayError message ]
    InGame table -> [ (Game.View.viewTable table) |> Html.map GameAction ]
    EndGame table info -> endGame table info.winner info.playAgainPressed
  )
