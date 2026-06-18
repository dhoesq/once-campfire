class Messages::PinsController < ApplicationController
  before_action :set_message

  def create
    @message.pin(by: Current.user)
    broadcast_pins
    head :no_content
  end

  def destroy
    @message.unpin
    broadcast_pins
    head :no_content
  end

  private
    def set_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end

    # Re-render the room's pinned bar for everyone in the room. The bar lives at
    # the top of the message list with a stable id, so a replace keeps it live
    # for the actor and every other connected client.
    def broadcast_pins
      room = @message.room
      Turbo::StreamsChannel.broadcast_replace_to room, :messages,
        target: ActionView::RecordIdentifier.dom_id(room, :pins),
        partial: "rooms/pins",
        locals: { room: room }
    end
end
