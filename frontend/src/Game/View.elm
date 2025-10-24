module Game.View exposing (viewTable, Deck(..), deckToId, idToDeck)

import Game.Cards exposing (Card)
import Game.Data exposing (Table, Player(..))
import Game.Events exposing (Action(..))

import Array
import Html exposing (..)
import Html.Keyed
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy exposing (..)
import Html.Events.Extra.Touch as Touch

viewTable : Table -> Html Game.Events.Action
viewTable table =
  div [ class "game" ] [
    (Html.Lazy.lazy5
      faceDownDeck
      Opponent
      table.opponentNumCards
      Nothing
      (getCardDealOffset table (Just Opponent) True)
      0
    )
    , eventLog table.eventLog
    , (centerDeck
         table.centerDeck
         (getCardDealOffset table table.cardDrawnFrom False)
       )
    , (Html.Lazy.lazy5
        faceDownDeck
        You
        table.yourNumCards
        (Just Game.Events.Draw)
        (getCardDealOffset table (Just You) True)
        table.invalidDrawCount
      )
    ]


type Deck
  = Center
  | Yours
  | Opponents

-- Element IDs of card decks
idToDeck : String -> Maybe Deck
idToDeck id =
  if (id == "center-deck") then Just Center
  else if (id == "your-deck") then Just Yours
  else if (id == "opponent-deck") then Just Opponents
  else Nothing

deckToId : Deck -> String
deckToId deck = case deck of
  Yours -> "your-deck"
  Opponents -> "opponent-deck"
  Center -> "center-deck"



faceDownDeck : Player -> Int -> Maybe Game.Events.Action -> String -> Int -> Html Game.Events.Action
faceDownDeck deckType size maybeAction offsetCoordinates invalidDrawCount =
  let
    deckClassName = if deckType == Opponent then "opponent-deck" else "your-deck"
    elementId = if deckType == Opponent then (deckToId Opponents) else (deckToId Yours)
    cardOffset = (-0.4, -0.6)
  in
  div
    ([
      class deckClassName
      , Html.Attributes.id elementId
      , class (case invalidDrawCount of
          0 -> ""
          _ -> if (modBy 2 invalidDrawCount) == 0 then "wiggle" else "wiggle-alt"
       )
     ]
    ++ case maybeAction of
      Just action -> [
          onClick action
          , Touch.onStart (\_ -> action)
        ]
      Nothing -> []
    )
    (List.map
      (\i -> (div [
        class "card card-back card-in-hand"
        , cssVariables [
            ("card-offset-x", (floatToPx ((toFloat i) * Tuple.first cardOffset)))
            , ("card-offset-y", (floatToPx ((toFloat i) * Tuple.second cardOffset)))
            , ("card-center-to-hand-offset", offsetCoordinates)
            , ("card-deal-to-hand-delay", (String.fromInt (i * 20)) ++ "ms")
          ]
        ] []))
      (List.range 0 (size - 1))
    )


centerDeck : List Game.Cards.Card -> String -> Html Game.Events.Action
centerDeck cards dealtCardOffset =
  Html.Keyed.ul
    [ class "center-deck"
    , Html.Attributes.id (deckToId Center)
    , Touch.onStart (\_ -> Game.Events.Snap)
    , onClick Game.Events.Snap
    ]
    ([("placeholder", div [ class "card card-ghost center-position" ] [] )]
    ++ (List.indexedMap
        (\i card -> (
            let
              isTop = ((i+1) == (List.length cards))
            in
            (Game.Cards.toString card
                , div ([
                    class "card card-front"
                    , cssVariables [
                        ("card-hand-to-center-offset", dealtCardOffset)
                        , ("card-offset-x", Tuple.first (getRandomTranslation i))
                        , ("card-offset-y", Tuple.second (getRandomTranslation i))
                        , ("card-rotation-z", getRandomRotation i)
                        , ("card-face-image", Game.Cards.cardFace card)
                    ]
                    ] ++ if isTop then [ class "center-top-card will-change" ] else []
                    )
                []
            )
            ))
        cards
        )
    ++ (let
            index = (List.length cards) - 1
        in if (List.length cards == 0) then [] else [("back-" ++ (String.fromInt index) , div [
                class "card card-back center-top-card center-top-card-back-face will-change"
                , cssVariables [
                    ("card-hand-to-center-offset", dealtCardOffset)
                    , ("card-offset-x", Tuple.first (getRandomTranslation index))
                    , ("card-offset-y", Tuple.second (getRandomTranslation index))
                    , ("card-rotation-z", getRandomRotation index)
                ]
            ] [])
            ]
        )
    )


getCardDealOffset : Game.Data.Table -> Maybe Game.Data.Player -> Bool -> String
getCardDealOffset table maybePlayer invert =
  let
    coords = case maybePlayer of
      Nothing -> (0, 0)
      Just player -> case player of
        You -> table.yourDeckOffset
        Opponent -> table.opponentDeckOffset
  in
    [Tuple.first coords, Tuple.second coords]
     |> List.map (\offset -> if invert then -offset else offset)
     |> List.map floatToPx
     |> List.map (\offset -> "calc(-50% + " ++ offset ++ ")")
     |> String.join " "


cssVariables : List (String, String) -> Attribute msg
cssVariables variables =
  Html.Attributes.attribute "style" (
    variables
      |> List.map (\item -> "--" ++ (Tuple.first item) ++ ": " ++ (Tuple.second item))
      |> String.join "; "
    )


eventLog : List String -> Html Game.Events.Action
eventLog events =
  Html.Keyed.ul [ class "event-log" ]
  (events
   |> List.reverse
   |> List.take 5
   |> List.map (\event -> (event, div [ class "event" ] [ text event ]))
  )

floatToPx : Float -> String
floatToPx float =
  (String.fromFloat float) ++ "px"

-- TODO: Make these actually random
getRandomRotation : Int -> String
getRandomRotation index =
  let
    angle = Array.fromList [3, 1, -2, 2, 6, -1, 2, -3, 2, 2, -3, 0, 4, -1, -6, 2, -10, 3, 0, 4, 0, -1, 6, -5, -1, 1, 10, 6, -1, 1, 7, -1, 0, 2, -3, 0, -1, -2, -2, 3, 3, 0, 0, 0, 0, 0, -4, 5, 0, -1, 2, -3]
      |> Array.get index
      |> Maybe.withDefault 0
  in
    (String.fromInt angle) ++ "deg"

getRandomTranslation : Int -> (String, String)
getRandomTranslation index =
    let
      xOffset = Array.fromList [5, 5, 1, 13, -1, -4, 1, 0, 0, -1, 3, -1, 3, 4, 0, -8, 1, -3, 3, -7, 3, 4, 3, 8, -2, 3, -1, 3, 0, -2, 8, 7, 6, 0, 1, -7, 2, 9, 0, 3, -4, 2, 4, -7, 0, -4, -3, -3, 0, 6, 0, -1]
          |> Array.get index
          |> Maybe.withDefault 0

      yOffset = Array.fromList [-12, -2, 6, -2, 0, -2, -3, -2, -1, 3, 0, -4, 1, 0, 0, 0, -1, 6, 7, 0, 0, 0, -3, 2, -1, -4, -5, 4, 1, -4, 0, 1, 2, -10, -5, 1, -5, 2, 12, 0, 2, 6, 0, 0, 0, 0, 5, 0, 0, -2, -1, -13]
          |> Array.get index
          |> Maybe.withDefault 0
    in
    ((String.fromInt xOffset) ++ "px", (String.fromInt yOffset) ++ "px")
