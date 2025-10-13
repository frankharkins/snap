pub struct InputMessage<UserId, Message> {
    pub sender: UserId,
    pub message: Message,
}

pub struct OutputMessage<UserId, Message> {
    pub recipient: UserId,
    pub message: Message,
}
