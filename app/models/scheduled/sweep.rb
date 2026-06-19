module Scheduled
  # One pass of the in-container scheduler: deliver every due scheduled message
  # and every due reminder. Each delivery is isolated in its own rescue so a
  # single bad row (a deleted room, an expired push subscription, etc.) logs and
  # is skipped rather than aborting the whole sweep. Both deliver! methods are
  # idempotent (guarded on delivered_at), so a row that errors after partial work
  # is safe to retry on the next sweep.
  class Sweep
    def self.run
      new.run
    end

    def run
      deliver_scheduled_messages
      deliver_reminders
    end

    private
      def deliver_scheduled_messages
        ScheduledMessage.due.find_each do |scheduled_message|
          begin
            scheduled_message.deliver!
          rescue => e
            Rails.logger.error "[sweep] ScheduledMessage##{scheduled_message.id} failed: #{e.class} #{e.message}"
          end
        end
      end

      def deliver_reminders
        Reminder.due.find_each do |reminder|
          begin
            reminder.deliver!
          rescue => e
            Rails.logger.error "[sweep] Reminder##{reminder.id} failed: #{e.class} #{e.message}"
          end
        end
      end
  end
end
