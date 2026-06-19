namespace :campfire do
  desc "Persistent in-container scheduler: deliver due scheduled messages + reminders every 60s (loads Rails once)"
  task sweep: :environment do
    Rails.logger.info "[sweep] starting persistent scheduler loop (interval 60s)"

    loop do
      begin
        Scheduled::Sweep.run
      rescue => e
        Rails.logger.error "[sweep] run failed: #{e.class} #{e.message}"
      end

      sleep 60
    end
  end
end
