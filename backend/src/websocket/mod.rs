use std::fmt;
use std::marker::PhantomData;

use futures_util::{SinkExt, StreamExt, TryFutureExt};

use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use warp::ws::Message;

/// Abstraction to handle websocket connections
pub struct WebSocketHandler<I: for<'de> Deserialize<'de>, O: Serialize> {
    send_channel: mpsc::Sender<Message>,
    cancellation_token: tokio_util::sync::CancellationToken,
    _phantom: PhantomData<(I, O)>,
}

impl<I: for<'de> Deserialize<'de> + Send, O: Serialize + fmt::Debug> WebSocketHandler<I, O> {
    /// Create a new websocket connection. `user_id` is for logging only.
    /// Websocket will disconnect when either client disconnects or `.close()` is called.
    /// The types are a bit upsetting but seem to work fine.
    pub fn new<EmptyFuture, EmptyFuture2>(
        ws: warp::ws::WebSocket,
        user_id: usize,
        mut on_message: impl FnMut(I) -> EmptyFuture + Send + 'static,
        mut on_disconnect: impl FnMut() -> EmptyFuture2 + Send + 'static,
    ) -> Self
    where
        EmptyFuture: Future<Output = ()> + Send,
        EmptyFuture2: Future<Output = ()> + Send,
    {
        let (mut ws_out, mut ws_in) = ws.split();

        // Use an channel bound to 25 messages to handle buffering and flushing of messages.
        // We don't have high throughput so 25 messages should be ample.
        let (send_channel, receive_channel) = mpsc::channel(25);
        let mut receive_channel = ReceiverStream::new(receive_channel);

        let cancellation_token = tokio_util::sync::CancellationToken::new();

        // Spawn a new task to read from the send channel and send messages
        // through the websocket.
        {
            let cancellation_token = cancellation_token.clone();
            tokio::task::spawn(async move {
                while let Some(message) = tokio::select! {
                    _ = cancellation_token.cancelled() => None,
                    maybe_message = receive_channel.next() => maybe_message
                } {
                    ws_out
                        .send(message)
                        .unwrap_or_else(|e| {
                            eprintln!("websocket send error: {}", e);
                            cancellation_token.cancel();
                        })
                        .await;
                }
            })
        };

        // Spawn a new task to read incoming messages and perform the
        // `on_message` function. This function also performs the
        // `on_disconnect` cleanup.
        {
            let cancellation_token = cancellation_token.clone();
            tokio::task::spawn(async move {
                while let Some(result) = tokio::select! {
                    _ = cancellation_token.cancelled() => None,
                    maybe_result = ws_in.next() => maybe_result
                } {
                    match parse_websocket_message(result) {
                        Ok(message) => on_message(message).await,
                        Err(_) => {
                            println!("Bad message from user {}", user_id)
                        }
                    }
                }
                println!("Disconnecting user {}", user_id);
                on_disconnect().await;
            })
        };

        WebSocketHandler {
            send_channel,
            cancellation_token,
            _phantom: PhantomData,
        }
    }

    pub fn send(&self, message: O) -> Result<(), ()> {
        let Ok(s) = serde_json::to_string(&message) else {
            println!("Could not serialize message: {:?}", &message);
            return Err(());
        };
        match self.send_channel.try_send(Message::text(s)) {
            Ok(()) => Ok(()),
            Err(_) => Err(()),
        }
    }

    pub fn close(&self) {
        self.cancellation_token.cancel();
    }
}

fn parse_websocket_message<I: for<'de> Deserialize<'de>, _E>(
    result: Result<Message, _E>,
) -> Result<I, ()> {
    let Ok(raw_message) = result else {
        return Err(());
    };
    let Ok(raw_string) = raw_message.to_str() else {
        return Err(());
    };
    let Ok(message) = serde_json::from_str(raw_string) else {
        return Err(());
    };
    return Ok(message);
}
