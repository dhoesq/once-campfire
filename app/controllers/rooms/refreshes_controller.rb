class Rooms::RefreshesController < ApplicationController
  include RoomScoped

  before_action :set_last_updated_at

  def show
    # The refresh (reconnect catch-up) repopulates the MAIN timeline, so it must
    # only carry ROOT messages. Thread replies created/updated since are excluded
    # here; they reach the thread panel via the per-thread broadcast instead.
    @new_messages = @room.messages.roots.with_creator.page_created_since(@last_updated_at)
    @updated_messages = @room.messages.roots.without(@new_messages).with_creator.page_updated_since(@last_updated_at)
  end

  private
    def set_last_updated_at
      @last_updated_at = Time.at(0, params[:since].to_i, :millisecond)
    end
end
