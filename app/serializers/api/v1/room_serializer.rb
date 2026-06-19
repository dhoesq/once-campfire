# ============================================================
# F-023a -- RoomSerializer (types.ts Room)
# ============================================================
# Room: {
#   id: string, name, kind: 'room' | 'dm',
#   unread_count: number, last_message_at: string | null
# }
#
# - kind: Rooms::Direct -> 'dm', everything else -> 'room'
# - DM name: the OTHER participant's name (Current.user excluded). For a self-DM
#   or a degenerate single-member DM, falls back to the current user's name.
# - unread_count: roots created after the caller's membership.unread_at. The web
#   UI's channel badge counts ROOT messages only (Room#receive skips thread
#   replies; Membership#unread_at is the read watermark). 0 when caller has read.
# - last_message_at: created_at of the room's most recent ROOT message, iso8601,
#   or null when the room has no messages.
module Api
  module V1
    class RoomSerializer
      # membership is the caller's Membership for this room (may be nil for the
      # serialization of a freshly created DM where we still pass it).
      def initialize(room, membership:, current_user:)
        @room = room
        @membership = membership
        @current_user = current_user
      end

      def as_json(*)
        {
          id: @room.id.to_s,
          name: name,
          kind: @room.is_a?(Rooms::Direct) ? "dm" : "room",
          unread_count: unread_count,
          last_message_at: last_message_at
        }
      end

      private

      def name
        if @room.is_a?(Rooms::Direct)
          other = @room.users.where.not(id: @current_user.id).first
          (other || @current_user).name
        else
          @room.name.to_s
        end
      end

      def unread_count
        return 0 if @membership.nil? || @membership.unread_at.nil?
        @room.messages.roots.where("messages.created_at > ?", @membership.unread_at).count
      rescue => e
        Rails.logger.warn("[api/v1] unread_count failed for room #{@room.id}: #{e.class} #{e.message}")
        0
      end

      def last_message_at
        last = @room.messages.roots.maximum(:created_at)
        last&.iso8601
      rescue => e
        Rails.logger.warn("[api/v1] last_message_at failed for room #{@room.id}: #{e.class} #{e.message}")
        nil
      end
    end
  end
end
