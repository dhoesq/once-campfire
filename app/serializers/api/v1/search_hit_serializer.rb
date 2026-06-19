# ============================================================
# F-023a -- SearchHitSerializer (types.ts SearchHit)
# ============================================================
# SearchHit: { message: Message, room: Room, snippet: string }
#   snippet: server-side HTML-stripped, bounded plain-text excerpt.
module Api
  module V1
    class SearchHitSerializer
      SNIPPET_LIMIT = 200

      def initialize(message, current_user:, membership:)
        @message = message
        @current_user = current_user
        @membership = membership
      end

      def as_json(*)
        {
          message: Api::V1::MessageSerializer.new(@message).as_json,
          room: Api::V1::RoomSerializer.new(@message.room, membership: @membership, current_user: @current_user).as_json,
          snippet: snippet
        }
      end

      private

      # HTML-stripped, truncated plain text. Uses the message's existing
      # plain_text_body (already HTML-free) and bounds it.
      def snippet
        text = @message.plain_text_body.to_s.strip.gsub(/\s+/, " ")
        text.length > SNIPPET_LIMIT ? "#{text[0, SNIPPET_LIMIT]}…" : text
      rescue => e
        Rails.logger.warn("[api/v1] snippet failed for message #{@message.id}: #{e.class} #{e.message}")
        ""
      end
    end
  end
end
