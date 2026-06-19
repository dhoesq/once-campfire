# F-023a -- GET /api/v1/rooms : the caller's rooms.
# Web UI sidebar shows the user's VISIBLE memberships (involvement != invisible).
# We mirror that scoping, then order by last activity desc (most recently active
# first), which is what the MC room list expects. Ordering is computed from the
# room's most recent ROOT message timestamp BEFORE serialization (cheap + no
# Time.parse round-trip).
module Api
  module V1
    class RoomsController < BaseController
      def index
        memberships = current_user.memberships.visible.includes(:room)

        ordered = memberships.sort_by do |m|
          last = m.room.messages.roots.maximum(:created_at)
          # Most recent first; rooms with no messages sort last.
          last ? -last.to_f : Float::INFINITY
        end

        json = ordered.map do |m|
          Api::V1::RoomSerializer.new(m.room, membership: m, current_user: current_user).as_json
        end
        render json: json
      end
    end
  end
end
