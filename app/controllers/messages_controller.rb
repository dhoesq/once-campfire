class MessagesController < ApplicationController
  include ActiveStorage::SetCurrent, RoomScoped

  before_action :set_room, except: :create
  before_action :set_message, only: %i[ show edit update destroy thread ]
  before_action :ensure_can_administer, only: %i[ edit update destroy ]

  layout false, only: :index

  def index
    @messages = find_paged_messages

    if @messages.any?
      fresh_when @messages
    else
      head :no_content
    end
  end

  def create
    set_room
    return head :forbidden if @room.archived?

    @message = @room.messages.create_with_attachment!(message_params)

    @message.broadcast_create
    deliver_webhooks_to_bots
  rescue ActiveRecord::RecordNotFound
    render action: :room_not_found
  end

  def show
  end

  # Renders the thread panel for a root message: the root plus its replies in
  # chronological order, with a thread-scoped composer. A reply target (a
  # message that is itself a reply) is resolved to its root so the panel always
  # shows the full thread.
  def thread
    @root = @message.thread_reply? ? @message.parent_message : @message
    @thread_replies = @root.thread_replies.with_creator.ordered
  end

  def edit
  end

  def update
    @message.update!(message_params)

    @message.broadcast_replace_to @room, :messages, target: [ @message, :presentation ], partial: "messages/presentation", attributes: { maintain_scroll: true }
    # ADDITIVE: plain-JSON realtime event for the MC mirror (best-effort).
    Api::V1::Realtime.message_updated(@message)
    redirect_to room_message_url(@room, @message)
  end

  def destroy
    @message.destroy
    @message.broadcast_remove
  end

  private
    def set_message
      @message = @room.messages.find(params[:id])
    end

    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?(@message)
    end


    # The main channel timeline shows ROOT messages only. Thread replies
    # (parent_message_id present) are excluded here so they never appear in the
    # main list; they live in the thread panel instead. The `.roots` filter is
    # applied to every pagination branch (initial last_page, before, after).
    def find_paged_messages
      case
      when params[:before].present?
        @room.messages.roots.with_creator.page_before(@room.messages.find(params[:before]))
      when params[:after].present?
        @room.messages.roots.with_creator.page_after(@room.messages.find(params[:after]))
      else
        @room.messages.roots.with_creator.last_page
      end
    end


    def message_params
      params.require(:message).permit(:body, :attachment, :client_message_id, :parent_message_id)
    end


    def deliver_webhooks_to_bots
      bots_eligible_for_webhook.excluding(@message.creator).each { |bot| bot.deliver_webhook_later(@message) }
    end

    def bots_eligible_for_webhook
      @room.direct? ? @room.users.active_bots : @message.mentionees.active_bots
    end
end
