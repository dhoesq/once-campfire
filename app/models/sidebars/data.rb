# Computes the data the sidebar renders for a given user: the membership groups
# (starred / direct / other), the per-room unread counts, and the direct-message
# placeholder users. Centralized here so both the request path (SidebarRendering
# concern) and the background broadcast path (Sidebars::Refresher) build the same
# assigns and cannot drift apart.
class Sidebars::Data
  DIRECT_PLACEHOLDERS = 20

  def self.for(user)
    new(user).assigns
  end

  def initialize(user)
    @user = user
  end

  # Returns the @-ivar names the sidebar partials read, as a plain Hash suitable
  # for ApplicationController.render(assigns:) or for copying into a controller.
  def assigns
    all_memberships = @user.memberships.visible.with_ordered_room

    starred = all_memberships.select(&:starred?).sort_by(&:starred_at).reverse
    non_starred = all_memberships.without(starred)
    direct = non_starred.select { |m| m.room.direct? }.sort_by { |m| m.room.updated_at }.reverse
    other = non_starred.without(direct)

    {
      starred_memberships: starred,
      direct_memberships: direct,
      other_memberships: other,
      unread_counts: unread_counts_for(all_memberships),
      direct_placeholder_users: direct_placeholder_users
    }
  end

  private
    # Hash of room_id => unread message count for the user's unread memberships.
    # Unread means messages at or after the membership's unread_at boundary,
    # excluding the user's own messages. The boundary is inclusive (>=) because
    # unread_at is set to the created_at of the first unread message: both
    # room.receive (new inbound message) and the mark-unread-from-here action
    # (Rooms::ReadsController) store the boundary message's own timestamp, so that
    # message must be counted. All boundaries resolve in one grouped query by
    # OR-ing a (room_id = ? AND created_at >= ?) clause per unread room. Fine for
    # the small number of rooms a member belongs to.
    def unread_counts_for(memberships)
      unread = memberships.select(&:unread?)
      return {} if unread.empty?

      clauses = unread.map { "(messages.room_id = ? AND messages.created_at >= ?)" }
      binds   = unread.flat_map { |m| [ m.room_id, m.unread_at ] }

      Message
        .where(clauses.join(" OR "), *binds)
        .where.not(creator_id: @user.id)
        .group(:room_id)
        .count
    end

    def direct_placeholder_users
      exclude_user_ids = user_ids_already_in_directs.including(@user.id)
      User.active.where.not(id: exclude_user_ids).order(:created_at).limit([ DIRECT_PLACEHOLDERS - exclude_user_ids.count, 0 ].max)
    end

    def user_ids_already_in_directs
      Membership.where(room_id: @user.rooms.directs.pluck(:id)).pluck(:user_id).uniq
    end
end
