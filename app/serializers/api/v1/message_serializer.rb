# ============================================================
# F-023a -- MessageSerializer (types.ts Message)
# ============================================================
# Message: {
#   id, room_id, user:{id,name,avatar_url}, body_html, mentions:[{user_id,name}],
#   created_at, updated_at, attachments:[Attachment], reactions:[Reaction]
# }
# Attachment: { id, filename, content_type, byte_size, url, preview_url? }
# Reaction:   { emoji, user_ids:[string], count }
# Mention:    { user_id, name }
#
# All ids -> strings. Timestamps -> iso8601.
#
# body_html uses the SAME rendering pipeline as the web UI
# (ContentFilters::TextMessagePresentationFilters over message.body.body) so the
# HTML the API returns is byte-identical to what Campfire renders in the browser.
# We do NOT hand-roll sanitization.
module Api
  module V1
    class MessageSerializer
      def initialize(message)
        @message = message
      end

      def as_json(*)
        {
          id: @message.id.to_s,
          room_id: @message.room_id.to_s,
          user: Api::V1::UserSerializer.new(@message.creator, include_email: false).author_json,
          body_html: body_html,
          mentions: mentions,
          created_at: @message.created_at.iso8601,
          updated_at: @message.updated_at.iso8601,
          attachments: attachments,
          reactions: reactions
        }
      end

      # Single reaction aggregate for one emoji (used by realtime reaction.added),
      # or nil if no boosters remain for that emoji.
      def reaction_for(emoji)
        boosters = @message.boosts.select { |b| b.content == emoji }
        return nil if boosters.empty?
        {
          emoji: emoji,
          user_ids: boosters.map { |b| b.booster_id.to_s },
          count: boosters.size
        }
      end

      private

      # Sanitized ActionText HTML, identical to the web UI's text presentation.
      # Attachment/sound messages render an HTML <body> too; for the API we only
      # emit the rich-text body HTML (attachments are surfaced separately in the
      # attachments[] array). Falls back to "" on any render error (never 500).
      def body_html
        content = @message.body&.body
        return "" if content.nil?
        ContentFilters::TextMessagePresentationFilters.apply(content).to_html
      rescue => e
        Rails.logger.warn("[api/v1] body_html failed for message #{@message.id}: #{e.class} #{e.message}")
        ""
      end

      # Parsed @mentions. Server-side ONLY (types.ts: MC must never parse).
      # Mirrors Message::Mentionee#mentioned_users:
      #   body.body.attachables.grep(User).uniq
      def mentions
        content = @message.body&.body
        return [] if content.nil?
        content.attachables.grep(User).uniq.map do |u|
          { user_id: u.id.to_s, name: u.name }
        end
      rescue => e
        Rails.logger.warn("[api/v1] mentions failed for message #{@message.id}: #{e.class} #{e.message}")
        []
      end

      # Reactions aggregated from boosts grouped by content (the emoji).
      def reactions
        @message.boosts.group_by(&:content).map do |emoji, boosters|
          {
            emoji: emoji,
            user_ids: boosters.map { |b| b.booster_id.to_s },
            count: boosters.size
          }
        end
      rescue => e
        Rails.logger.warn("[api/v1] reactions failed for message #{@message.id}: #{e.class} #{e.message}")
        []
      end

      # ActiveStorage attachment(s). Campfire attaches at most one file per
      # message (has_one_attached :attachment), but the contract is an array.
      def attachments
        return [] unless @message.attachment.attached?
        blob = @message.attachment.blob
        att = {
          id: blob.id.to_s,
          filename: blob.filename.to_s,
          content_type: blob.content_type,
          byte_size: blob.byte_size,
          url: Api::V1::UrlBuilder.rails_blob_url(blob)
        }
        att[:preview_url] = preview_url(@message.attachment)
        [ att ]
      rescue => e
        Rails.logger.warn("[api/v1] attachments failed for message #{@message.id}: #{e.class} #{e.message}")
        []
      end

      # Thumbnail/preview URL for representable images, else nil. Best-effort.
      def preview_url(attachment)
        return nil unless attachment.representable?
        rep = attachment.representation(:thumb)
        Api::V1::UrlBuilder.rails_representation_url(rep)
      rescue
        nil
      end
    end
  end
end
