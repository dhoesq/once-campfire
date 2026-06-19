class ScheduledMessagesController < ApplicationController
  before_action :set_scheduled_message, only: :destroy

  def index
    @scheduled_messages = Current.user.scheduled_messages
      .pending
      .where(room_id: Current.user.rooms)
      .includes(:room)
      .order(deliver_at: :asc)
      .limit(200)
  end

  # Schedule a message for later delivery. The room must be one the current user
  # belongs to and is not archived. An empty body or a missing/invalid
  # deliver_at is a no-op (the composer also guards empty bodies client-side).
  def create
    room = Current.user.rooms.find_by(id: params[:room_id])
    return respond_no_room unless room
    return respond_invalid if room.archived?

    deliver_at = parse_time(params[:deliver_at])
    body = params[:body].to_s

    if deliver_at.blank? || deliver_at <= Time.current || body.strip.empty?
      return respond_invalid
    end

    Current.user.scheduled_messages.create!(
      room: room,
      body: body,
      deliver_at: deliver_at,
      client_message_id: params[:client_message_id].presence
    )

    respond_to do |format|
      format.turbo_stream { head :created }
      format.html { redirect_to scheduled_messages_path, notice: "Message scheduled." }
      format.json { head :created }
    end
  end

  def destroy
    @scheduled_message.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(
          ActionView::RecordIdentifier.dom_id(@scheduled_message)
        )
      end
      format.html { redirect_to scheduled_messages_path, notice: "Scheduled message cancelled." }
      format.json { head :no_content }
    end
  end

  private
    def set_scheduled_message
      # Scope to the current user as creator so a user can only cancel their own.
      @scheduled_message = Current.user.scheduled_messages.find(params[:id])
    end

    def parse_time(value)
      return nil if value.blank?
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def respond_no_room
      respond_to do |format|
        format.turbo_stream { head :not_found }
        format.html { head :not_found }
        format.json { head :not_found }
      end
    end

    def respond_invalid
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { head :unprocessable_entity }
        format.json { head :unprocessable_entity }
      end
    end
end
