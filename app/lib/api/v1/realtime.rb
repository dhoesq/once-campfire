# ============================================================
# F-023b — plain-JSON realtime fan-out (publisher side)
# ============================================================
# The /api/v1 realtime gateway (Api::V1::WsGateway) exposes a plain-JSON
# WebSocket. This module is the PUBLISH half: wherever the app already fires a
# Turbo Stream broadcast for a message/boost change, we ALSO publish a plain
# JSON event here. The existing Turbo broadcasts are NOT touched -- this is
# purely additive, a parallel surface for Mission Control.
#
# Transport: Redis pub/sub on a DEDICATED channel namespace
#   api:v1:room:<room_id>
# We use a raw Redis connection (REDIS_URL) rather than ActionCable.server
# .broadcast so the gateway can consume bare event JSON without the
# ActionCable envelope -- campfireSocket.ts expects bare frames.
#
# Event shapes are the locked contract (types.ts CampfireEvent):
#   message.created  { type, room_id, message }
#   message.updated  { type, room_id, message }
#   message.deleted  { type, room_id, message_id }
#   reaction.added   { type, room_id, message_id, reaction }
#   presence.changed { type, room_id, user_id, present }
#
# Publishing is best-effort: a Redis hiccup must never break the web UI's
# message create/update/delete. All errors are swallowed + logged.
module Api
  module V1
    module Realtime
      CHANNEL_PREFIX = "api:v1:room:".freeze

      class << self
        def channel_for(room_id)
          "#{CHANNEL_PREFIX}#{room_id}"
        end

        # Publish an event to a room's channel. The event Hash is built INSIDE
        # the rescue (via the block) so that ALL work -- including serialization
        # -- is best-effort. These helpers are now called from the core web
        # broadcast path (Message::Broadcasts), so a Redis hiccup OR a serializer
        # error must NEVER break the web UI's message create/update/delete. The
        # block is only evaluated here, never outside this rescue.
        def publish(room_id)
          event = yield
          redis.publish(channel_for(room_id), event.to_json)
        rescue => e
          Rails.logger.warn("[api/v1/realtime] publish failed for room #{room_id}: #{e.class} #{e.message}")
          nil
        end

        # --- Typed helpers, called from the additive broadcast hooks. ---

        def message_created(message)
          publish(message.room_id) do
            {
              type: "message.created",
              room_id: message.room_id.to_s,
              message: Api::V1::MessageSerializer.new(message).as_json
            }
          end
        end

        def message_updated(message)
          publish(message.room_id) do
            {
              type: "message.updated",
              room_id: message.room_id.to_s,
              message: Api::V1::MessageSerializer.new(message).as_json
            }
          end
        end

        def message_deleted(room_id:, message_id:)
          publish(room_id) do
            {
              type: "message.deleted",
              room_id: room_id.to_s,
              message_id: message_id.to_s
            }
          end
        end

        # A boost (reaction) was added/removed -- we re-emit the full current
        # reaction aggregate for that emoji so consumers can replace state.
        def reaction_added(message:, emoji:)
          publish(message.room_id) do
            reaction = Api::V1::MessageSerializer.new(message).reaction_for(emoji)
            # If the emoji no longer has any boosters (last one removed), emit a
            # zero-count reaction so the consumer can drop it.
            reaction ||= { emoji: emoji, user_ids: [], count: 0 }
            {
              type: "reaction.added",
              room_id: message.room_id.to_s,
              message_id: message.id.to_s,
              reaction: reaction
            }
          end
        end

        def presence_changed(room_id:, user_id:, present:)
          publish(room_id) do
            {
              type: "presence.changed",
              room_id: room_id.to_s,
              user_id: user_id.to_s,
              present: present
            }
          end
        end

        # A dedicated Redis connection for publishing. Reused process-wide.
        def redis
          @redis ||= Redis.new(url: redis_url)
        end

        def redis_url
          ENV.fetch("REDIS_URL", "redis://localhost:6379")
        end
      end
    end
  end
end
