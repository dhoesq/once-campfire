class Reminder < ApplicationRecord
  belongs_to :user
  belongs_to :message

  scope :pending, -> { where(delivered_at: nil) }
  scope :due, -> { pending.where("remind_at <= ?", Time.current) }
  scope :ordered, -> { order(remind_at: :asc) }

  # Fire a web push to the reminding user's subscriptions, reusing the exact same
  # machinery a room message push uses: build a {title:, body:, path:} payload
  # and hand the user's Push::Subscription relation to the shared web_push_pool,
  # which calls subscription.notification(**payload) (badge supplied there).
  #
  # Idempotent: guarded on delivered_at. If the user has no push subscriptions we
  # still mark it delivered so the reminder shows as fired in the Reminders list
  # and is never re-swept (no crash, no infinite retry).
  def deliver!
    return if delivered_at.present?

    subscriptions = user.push_subscriptions
    if subscriptions.exists?
      Rails.configuration.x.web_push_pool.queue(payload, subscriptions)
    end

    update!(delivered_at: Time.current)
  end

  private
    def payload
      {
        title: "⏰ Reminder",
        body: snippet,
        path: Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
      }
    end

    # Plain-text preview of the message, truncated so the push body stays short.
    def snippet
      message.plain_text_body.to_s.truncate(140)
    end
end
