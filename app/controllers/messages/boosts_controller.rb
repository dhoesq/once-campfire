class Messages::BoostsController < ApplicationController
  before_action :set_message

  def index
  end

  def new
  end

  def create
    @boost = @message.boosts.create!(boost_params)

    broadcast_create
    # ADDITIVE (F-023b): plain-JSON reaction event for the MC realtime gateway.
    # Does not touch the Turbo broadcast above. Re-reads the message's boosts so
    # the emitted aggregate reflects the just-created boost.
    Api::V1::Realtime.reaction_added(message: @boost.message.reload, emoji: @boost.content)
    redirect_to message_boosts_url(@message)
  end

  def destroy
    @boost = Current.user.boosts.find(params[:id])
    emoji = @boost.content
    message = @boost.message
    @boost.destroy!

    broadcast_remove
    # ADDITIVE (F-023b): re-emit the emoji's current aggregate (now smaller, or
    # zero-count if the last boost was removed) so MC can update/drop it.
    Api::V1::Realtime.reaction_added(message: message.reload, emoji: emoji)
  end

  private
    def set_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end

    def boost_params
      params.require(:boost).permit(:content)
    end

    def broadcast_create
      @boost.broadcast_append_to @boost.message.room, :messages,
        target: "boosts_message_#{@boost.message.client_message_id}", partial: "messages/boosts/boost", attributes: { maintain_scroll: true }
    end

    def broadcast_remove
      @boost.broadcast_remove_to @boost.message.room, :messages
    end
end
