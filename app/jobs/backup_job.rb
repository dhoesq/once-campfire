# frozen_string_literal: true

# Runs the disaster-recovery export on a Resque worker, which shares the SQLite
# volume and Active Storage tree with the web process. Inert when R2 is not
# configured (see Backups::Export).
class BackupJob < ApplicationJob
  def perform
    Backups::Export.run
  end
end
