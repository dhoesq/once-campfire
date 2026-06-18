# Re-renders and broadcasts the sidebar for each user whose unread state changed
# when a message was received, so their unread-count badges update live. Enqueued
# from Room#receive after the memberships have been marked unread.
class Room::RefreshSidebarsJob < ApplicationJob
  def perform(user_ids)
    User.where(id: user_ids).find_each do |user|
      # Best-effort live update: a render failure for one user must never break
      # the others or retry-loop the worker on every message. Skip and log.
      begin
        Sidebars::Refresher.refresh(user)
      rescue => e
        Rails.logger.error("RefreshSidebarsJob: sidebar refresh failed for user #{user.id}: #{e.class} #{e.message}")
      end
    end
  end
end
