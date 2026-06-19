# frozen_string_literal: true

# Machine-triggered disaster-recovery backup endpoint.
#
# POST /backups
#
# This endpoint is called by an external scheduler (cron / Railway scheduled job
# / uptime hook), not by a logged-in human, so it skips the normal session login
# and bot-deny before_actions and instead authenticates with a constant-time
# token comparison against ENV["BACKUP_TOKEN"].
#
# It only ENQUEUES BackupJob and returns 202 (or 401). It never runs the heavy
# work inline and never returns any application data, so it can neither time out
# the request nor leak chat content.
class BackupsController < ApplicationController
  allow_unauthenticated_access only: :create
  allow_bot_access only: :create
  skip_before_action :verify_authenticity_token, only: :create, raise: false

  def create
    return head :unauthorized unless authorized?

    BackupJob.perform_later
    head :accepted
  end

  private
    def authorized?
      expected = ENV["BACKUP_TOKEN"].to_s
      return false if expected.empty?

      ActiveSupport::SecurityUtils.secure_compare(provided_token, expected)
    end

    def provided_token
      from_header = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
      (from_header || params[:token]).to_s
    end
end
