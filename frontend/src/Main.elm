port module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D



-- MAIN


main : Program () Model Msg
main =
  Browser.element
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }




-- PORTS


port connect : String -> Cmd msg
port sendMessage : String -> Cmd msg
port messageReceived : (String -> msg) -> Sub msg
port connectionLost : (() -> msg) -> Sub msg
port connectionStarted : (() -> msg) -> Sub msg



-- MODEL


type alias Model =
  { draft : String
  , messages : List String
  , isConnected: Bool
  , joinGameId : String
  }


init : () -> ( Model, Cmd Msg )
init _ =
  ( { draft = "", joinGameId = "", messages = [], isConnected = False }
  , Cmd.none
  )



-- UPDATE


type Msg
  = DraftChanged String
  | JoinGameIdChanged String
  | Send
  | CreateGame
  | JoinGame String
  | MessageReceived String
  | ConnectionStarted ()
  | ConnectionLost ()


-- Use the `sendMessage` port when someone presses ENTER or clicks
-- the "Send" button. Check out index.html to see the corresponding
-- JS where this is piped into a WebSocket.
--
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    DraftChanged draft ->
      ( { model | draft = draft }
      , Cmd.none
      )
    Send ->
      ( { model | draft = "" }
      , sendMessage model.draft
      )
    MessageReceived message ->
      ( { model | messages = model.messages ++ [message] }
      , Cmd.none
      )
    CreateGame ->
      (model, connect "ws://localhost:3030/create")
    JoinGameIdChanged id ->
      ( { model | joinGameId = id }
      , Cmd.none
      )
    JoinGame id ->
      (model, connect ("ws://localhost:3030/join/" ++ id))
    ConnectionStarted _ ->
      ( { model | isConnected = True }
      , Cmd.none
      )
    ConnectionLost _ ->
      ( { model | isConnected = False }
      , Cmd.none
      )



-- SUBSCRIPTIONS


-- Subscribe to the `messageReceiver` port to hear about messages coming in
-- from JS. Check out the index.html file to see how this is hooked up to a
-- WebSocket.
--
subscriptions : Model -> Sub Msg
subscriptions model =
  case model.isConnected of
    True -> Sub.batch [ messageReceived MessageReceived, connectionLost ConnectionLost]
    False -> connectionStarted ConnectionStarted


-- VIEW


view : Model -> Html Msg
view model =
  div []
    ([ h1 [] [ text "Echo Chat" ]] ++
      if model.isConnected then
        [ ul []
            (List.map (\msg -> li [] [ text msg ]) model.messages)
        , input
            [ type_ "text"
            , placeholder "Draft"
            , onInput DraftChanged
            , on "keydown" (ifIsEnter Send)
            , value model.draft
            ]
            []
        , button [ onClick Send ] [ text "Send" ]
        ]
      else
        [
           input
            [ type_ "text"
            , placeholder "Draft"
            , onInput JoinGameIdChanged
            , value model.joinGameId
            ]
            []
          , button [ onClick (JoinGame model.joinGameId) ] [ text "Join" ]
          , button [ onClick CreateGame ] [ text "Create" ]
        ]
    )



-- DETECT ENTER


ifIsEnter : msg -> D.Decoder msg
ifIsEnter msg =
  D.field "key" D.string
    |> D.andThen (\key -> if key == "Enter" then D.succeed msg else D.fail "some other key")
