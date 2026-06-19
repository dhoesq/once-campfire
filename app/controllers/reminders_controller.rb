class RemindersController < ApplicationController
  before_action :set_reminder, only: :destroy

  def index
    @reminders = Current.user.reminders
      .pending
      .where(message_id: Current.user.reachable_messages)
      .includes(message: { room: [] })
      .order(remind_at: :asc)
      .limit(200)
  end

  # Set a personal reminder for a reachable message. A user can only remind
  # themselves, and only about a message in a room they belong to (enforced via
  # reachable_messages). An invalid/missing remind_at is a no-op.
  def create
    message = Current.user.reachable_messages.find_by(id: params[:message_id])
    return respond_invalid unless message

    remind_at = parse_time(params[:remind_at])
    return respond_invalid if remind_at.blank? || remind_at <= Time.current

    Current.user.reminders.create!(message: message, remind_at: remind_at)

    respond_to do |format|
      format.turbo_stream { head :created }
      format.html { redirect_to reminders_path, notice: "Reminder set." }
      format.json { head :created }
    end
  end

  def destroy
    @reminder.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(
          ActionView::RecordIdentifier.dom_id(@reminder)
        )
      end
      format.html { redirect_to reminders_path, notice: "Reminder cancelled." }
      format.json { head :no_content }
    end
  end

  private
    def set_reminder
      # Scope to the current user so a user can only cancel their own reminders.
      @reminder = Current.user.reminders.find(params[:id])
    end

    def parse_time(value)
      return nil if value.blank?
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def respond_invalid
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { head :unprocessable_entity }
        format.json { head :unprocessable_entity }
      end
    end
end
