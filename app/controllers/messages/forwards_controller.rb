class Messages::ForwardsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :set_source_message

  def new
    @rooms = Current.user.rooms.without_directs.ordered + Current.user.rooms.directs
  end

  def create
    target_room = Current.user.rooms.find(params[:room_id])

    message = target_room.messages.create!(
      creator: Current.user,
      body: forwarded_body
    )

    message.broadcast_create
    deliver_webhooks_to_bots(message, target_room)
    redirect_to room_message_url(target_room, message)
  end

  private
    def set_source_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end

    # Mirror MessagesController#deliver_webhooks_to_bots for the forwarded copy:
    # notify mentioned bots (or, in a direct room, member bots), excluding the
    # forwarder, so forwarded messages reach bots like normal messages do.
    def deliver_webhooks_to_bots(message, room)
      eligible = room.direct? ? room.users.active_bots : message.mentionees.active_bots
      eligible.excluding(message.creator).each { |bot| bot.deliver_webhook_later(message) }
    end

    # Build the forwarded rich-text body: an attribution line plus the original
    # message body quoted. Attachments are not re-attached in v1; if the source
    # had one, we note it in the attribution.
    def forwarded_body
      helpers = ApplicationController.helpers
      source_label = helpers.room_display_name(@message.room, for_user: Current.user)

      attribution = "Forwarded from #{source_label} (#{@message.creator.name})"
      attribution += " (original had an attachment)" if @message.attachment?

      original_html = @message.body.body.to_html.presence || ERB::Util.html_escape(@message.plain_text_body)

      ActionText::Content.new(
        helpers.tag.div(helpers.tag.em(attribution)) +
        helpers.tag.blockquote(original_html.html_safe)
      )
    end
end
