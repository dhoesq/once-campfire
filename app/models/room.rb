class Room < ApplicationRecord
  has_many :memberships, dependent: :delete_all do
    def grant_to(users)
      room = proxy_association.owner
      Membership.insert_all(Array(users).collect { |user| { room_id: room.id, user_id: user.id, involvement: room.default_involvement } })
    end

    def revoke_from(users)
      destroy_by user: users
    end

    def revise(granted: [], revoked: [])
      transaction do
        grant_to(granted) if granted.present?
        revoke_from(revoked) if revoked.present?
      end
    end
  end

  has_many :users, through: :memberships
  has_many :messages, dependent: :destroy

  belongs_to :creator, class_name: "User", default: -> { Current.user }

  scope :opens,           -> { where(type: "Rooms::Open") }
  scope :closeds,         -> { where(type: "Rooms::Closed") }
  scope :directs,         -> { where(type: "Rooms::Direct") }
  scope :without_directs, -> { where.not(type: "Rooms::Direct") }

  scope :active,   -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  scope :ordered, -> { order("LOWER(name)") }

  class << self
    def create_for(attributes, users:)
      transaction do
        create!(attributes).tap do |room|
          room.memberships.grant_to users
        end
      end
    end

    def original
      order(:created_at).first
    end
  end

  def receive(message)
    # Thread replies do not affect the MAIN channel's unread state or fire a
    # channel push: they belong to a thread, not the channel timeline, and the
    # channel unread badge counts roots only. Per-thread unread/notify is a
    # deferred v1 follow-up. A root (normal) message keeps the existing behavior.
    return if message.thread_reply?

    unread_memberships(message)
    push_later(message)
  end

  def open?
    is_a?(Rooms::Open)
  end

  def closed?
    is_a?(Rooms::Closed)
  end

  def direct?
    is_a?(Rooms::Direct)
  end

  def default_involvement
    "mentions"
  end

  # Archiving freezes a channel: it disappears from active sidebars and becomes
  # read-only, while its history stays viewable. Directs (Pings) are never
  # archivable; use deletion for those instead.
  def archivable?
    !direct?
  end

  def archived?
    archived_at.present?
  end

  def archive
    return false unless archivable?
    update!(archived_at: Time.current)
  end

  def unarchive
    update!(archived_at: nil)
  end

  private
    def unread_memberships(message)
      affected = memberships.visible.disconnected.where.not(user: message.creator)
      # Capture before update_all (which returns a row count, not records) so we
      # can refresh exactly the users whose unread count just changed.
      user_ids = affected.pluck(:user_id)
      affected.update_all(unread_at: message.created_at, updated_at: Time.current)

      refresh_sidebars_later(user_ids)
    end

    def refresh_sidebars_later(user_ids)
      Room::RefreshSidebarsJob.perform_later(user_ids) if user_ids.any?
    end

    def push_later(message)
      Room::PushMessageJob.perform_later(self, message)
    end
end
