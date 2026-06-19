# F-023a -- GET /api/v1/search?q=
# Uses the existing FTS5 scope Message.search(q). Results are scoped to the
# caller's rooms (no cross-room leakage). Maps each hit to
# { message, room, snippet }. Never 500s -- a bad FTS query yields [].
module Api
  module V1
    class SearchesController < BaseController
      LIMIT = 50

      def index
        q = params[:q].to_s
        return render(json: { error: "q_required" }, status: :unprocessable_entity) if q.blank?

        room_ids = current_user.rooms.pluck(:id)
        return render(json: []) if room_ids.empty?

        # Membership lookup table so each hit's RoomSerializer gets the caller's
        # membership (for unread_count) without an N+1 per hit.
        memberships_by_room = current_user.memberships.index_by(&:room_id)

        messages = Message.search(sanitize_fts(q))
                          .where(room_id: room_ids)
                          .with_creator.with_boosts.with_attachment_details
                          .limit(LIMIT)
                          .to_a

        hits = messages.map do |m|
          Api::V1::SearchHitSerializer.new(
            m, current_user: current_user, membership: memberships_by_room[m.room_id]
          ).as_json
        end
        render json: hits
      rescue => e
        # FTS5 raises on malformed match syntax -- treat as no results, not 500.
        Rails.logger.warn("[api/v1] search failed for q=#{q.inspect}: #{e.class} #{e.message}")
        render json: []
      end

      private

      # FTS5 treats unbalanced quotes / operators as syntax errors. Wrap the
      # query as a quoted phrase so arbitrary user text is matched literally,
      # escaping embedded double-quotes per FTS5 rules ("" = literal ").
      def sanitize_fts(q)
        %("#{q.gsub('"', '""')}")
      end
    end
  end
end
