# F-023a -- messages: list / create / update / delete.
# This is a PARALLEL surface to the web MessagesController. It reproduces the
# web UI's create side effects EXACTLY (broadcast_create + room.receive unread +
# webhooks to bots) so a message posted via the API behaves identically to one
# posted in the browser -- and ADDITIVELY publishes the plain-JSON realtime
# event for MC.
module Api
  module V1
    class MessagesController < BaseController
      MAX_BODY_BYTES = 100_000 # guard against absurd payloads (422)

      # GET /api/v1/rooms/:room_id/messages?before&limit
      # ROOT messages only (thread replies live in the thread panel, never the
      # main timeline -- matches MessagesController#find_paged_messages .roots).
      # Cursor: `before` = message id; return rows with id < before.
      # Order: DESC by id + LIMIT, then reversed to ascending (oldest->newest)
      # which is how MC's MessageList renders.
      def index
        room = require_member!(params[:room_id])&.room
        return if performed?

        scope = room.messages.roots.with_creator.with_boosts.with_attachment_details
        if params[:before].present?
          before_id = params[:before].to_i
          scope = scope.where("messages.id < ?", before_id) if before_id.positive?
        end

        messages = scope.order(id: :desc).limit(clamped_limit).to_a.reverse
        render json: messages.map { |m| Api::V1::MessageSerializer.new(m).as_json }
      rescue ActiveRecord::RecordNotFound
        not_found!
      end

      # POST /api/v1/rooms/:room_id/messages  body: { body }
      def create
        membership = require_member!(params[:room_id])
        return if performed?
        room = membership.room

        return render(json: { error: "room_archived" }, status: :unprocessable_entity) if room.archived?

        body = params[:body]
        return render(json: { error: "body_required" }, status: :unprocessable_entity) if body.blank?
        return render(json: { error: "body_too_long" }, status: :unprocessable_entity) if body.to_s.bytesize > MAX_BODY_BYTES

        # NORMAL create path: after_create_commit -> room.receive(self) handles
        # unread + push exactly like the web UI. Mentions are parsed by the model
        # from the rich-text body automatically (Message::Mentionee). creator is
        # Current.user (set in BaseController).
        message = room.messages.create!(body: body, creator: current_user)

        # Same explicit Turbo broadcast the web controller fires (the model does
        # NOT auto-broadcast on create; the controller does). broadcast_create
        # ALSO publishes the plain-JSON realtime event for the MC gateway, so we
        # do not emit it again here.
        message.broadcast_create

        # Same bot webhook delivery as the web controller.
        deliver_webhooks_to_bots(room, message)

        render json: Api::V1::MessageSerializer.new(message).as_json, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: "invalid", detail: e.message }, status: :unprocessable_entity
      end

      # PATCH /api/v1/messages/:id  body: { body }
      # Web UI rule: only an admin OR the creator may edit (can_administer?).
      def update
        message = Current.user.reachable_messages.find_by(id: params[:id])
        return not_found! if message.nil?
        return head(:forbidden) unless current_user.can_administer?(message)

        body = params[:body]
        return render(json: { error: "body_required" }, status: :unprocessable_entity) if body.blank?
        return render(json: { error: "body_too_long" }, status: :unprocessable_entity) if body.to_s.bytesize > MAX_BODY_BYTES

        message.update!(body: body)

        # Mirror the web controller's edit broadcast (replace presentation).
        message.broadcast_replace_to message.room, :messages,
          target: [ message, :presentation ], partial: "messages/presentation",
          attributes: { maintain_scroll: true }

        Api::V1::Realtime.message_updated(message)

        render json: Api::V1::MessageSerializer.new(message).as_json
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: "invalid", detail: e.message }, status: :unprocessable_entity
      end

      # DELETE /api/v1/messages/:id
      # Web UI rule: only an admin OR the creator may delete (can_administer?).
      def destroy
        message = Current.user.reachable_messages.find_by(id: params[:id])
        return not_found! if message.nil?
        return head(:forbidden) unless current_user.can_administer?(message)

        message.destroy
        # broadcast_remove also publishes the plain-JSON message.deleted event.
        message.broadcast_remove

        head :no_content
      end

      private

      # Mirrors MessagesController#deliver_webhooks_to_bots / bots_eligible.
      def deliver_webhooks_to_bots(room, message)
        eligible = room.direct? ? room.users.active_bots : message.mentionees.active_bots
        eligible.excluding(message.creator).each { |bot| bot.deliver_webhook_later(message) }
      rescue => e
        Rails.logger.warn("[api/v1] bot webhook delivery failed for message #{message.id}: #{e.class} #{e.message}")
      end
    end
  end
end
