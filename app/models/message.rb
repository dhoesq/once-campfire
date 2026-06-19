class Message < ApplicationRecord
  include Attachment, Broadcasts, Mentionee, Pagination, Searchable

  belongs_to :room, touch: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :pinned_by, class_name: "User", optional: true
  belongs_to :parent_message, class_name: "Message", optional: true

  has_many :boosts, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :reminders, dependent: :destroy
  has_many :thread_replies, class_name: "Message", foreign_key: :parent_message_id, dependent: :destroy

  has_rich_text :body

  before_create -> { self.client_message_id ||= Random.uuid } # Bots don't care
  # Replies are flattened: a reply to a reply attaches to that reply's root, so
  # parent_message_id always points at a root message (Slack-style flat threads).
  before_create :flatten_thread_parent, if: :thread_reply?
  after_create_commit -> { room.receive(self) }

  scope :ordered, -> { order(:created_at) }
  scope :roots, -> { where(parent_message_id: nil) }
  scope :pinned,  -> { where.not(pinned_at: nil).order(pinned_at: :desc) }
  scope :with_creator, -> { preload(creator: :avatar_attachment) }
  scope :with_attachment_details, -> {
    with_rich_text_body_and_embeds
    with_attached_attachment
      .includes(attachment_blob: :variant_records)
  }
  scope :with_boosts, -> { includes(boosts: :booster) }

  def plain_text_body
    body.to_plain_text.presence || attachment&.filename&.to_s || ""
  end

  def pinned?
    pinned_at.present?
  end

  # True when this message is a reply inside a thread (it hangs off a root).
  def thread_reply?
    parent_message_id.present?
  end

  # Count of replies in this message's thread. Only meaningful on a root.
  def thread_reply_count
    thread_replies.count
  end

  # Most recent reply in this message's thread, or nil. Only meaningful on a root.
  def last_thread_reply
    thread_replies.ordered.last
  end

  def pin(by:)
    update!(pinned_at: Time.current, pinned_by: by)
  end

  def unpin
    update!(pinned_at: nil, pinned_by: nil)
  end

  def to_key
    [ client_message_id ]
  end

  def content_type
    case
    when attachment?    then "attachment"
    when sound.present? then "sound"
    else                     "text"
    end.inquiry
  end

  def sound
    plain_text_body.match(/\A\/play (?<name>\w+)\z/) do |match|
      Sound.find_by_name match[:name]
    end
  end

  private
    # Ensure parent_message_id always points at a ROOT. If a user replies to a
    # message that is itself a reply, re-point to that reply's root so threads
    # stay one level deep (Slack-style flat threads).
    def flatten_thread_parent
      if parent_message&.thread_reply?
        self.parent_message_id = parent_message.parent_message_id
      end
    end
end
