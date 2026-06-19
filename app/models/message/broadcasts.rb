module Message::Broadcasts
  def broadcast_create
    if thread_reply?
      broadcast_thread_reply_create
    else
      broadcast_append_to room, :messages, target: [ room, :messages ]
      ActionCable.server.broadcast("unread_rooms", { roomId: room.id })
    end
  end

  def broadcast_remove
    broadcast_remove_to room, :messages
  end

  private
    # A thread reply must NOT land in the main room timeline. Instead it appends
    # to a per-thread stream (so an open thread panel updates live) and refreshes
    # the root message's presentation in the main timeline so its "N replies"
    # indicator stays current. The main :messages stream is untouched, so the
    # normal channel view never sees the reply.
    def broadcast_thread_reply_create
      root = parent_message
      return unless root

      broadcast_append_to(
        [ room, :thread, root.id ],
        target: [ root, :thread_replies ],
        partial: "messages/message",
        locals: { message: self }
      )

      root.broadcast_replace_to(
        room, :messages,
        target: [ root, :thread_indicator ],
        partial: "messages/thread_indicator",
        locals: { message: root }
      )
    end
end
