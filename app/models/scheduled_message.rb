class ScheduledMessage < ApplicationRecord
  belongs_to :room
  belongs_to :creator, class_name: "User"

  scope :pending, -> { where(delivered_at: nil) }
  scope :due, -> { pending.where("deliver_at <= ?", Time.current) }
  scope :ordered, -> { order(deliver_at: :asc) }

  # Post the scheduled message into the room as the creator using the SAME path a
  # live message takes: Message creation fires the after_create_commit
  # `room.receive(self)` hook (unread counts + push), and we additionally mirror
  # MessagesController#create by broadcasting the append and delivering bot
  # webhooks. The result is indistinguishable from a message typed right now.
  #
  # Idempotent: guarded on delivered_at so a double-sweep (or a retry after a
  # mid-run crash) never posts twice.
  def deliver!
    return if delivered_at.present?

    message = nil

    transaction do
      # Re-check inside the row lock so two concurrent sweeps can't both post.
      locked = self.class.lock.find(id)
      return if locked.delivered_at.present?

      message = room.messages.create!(
        creator: creator,
        body: body,
        client_message_id: client_message_id.presence
      )

      update!(delivered_at: Time.current)
    end

    # Broadcasts + webhooks happen OUTSIDE the transaction, mirroring the
    # controller, so a broadcast hiccup can never roll back a delivered message.
    if message
      message.broadcast_create
      deliver_webhooks_to_bots(message)
    end

    message
  end

  private
    # Mirror of MessagesController#deliver_webhooks_to_bots so scheduled posts
    # notify bots exactly like live posts. A direct room notifies its bots; a
    # shared room notifies bots that were @-mentioned in the body.
    def deliver_webhooks_to_bots(message)
      bots = room.direct? ? room.users.active_bots : message.mentionees.active_bots
      bots.excluding(message.creator).each { |bot| bot.deliver_webhook_later(message) }
    end
end
