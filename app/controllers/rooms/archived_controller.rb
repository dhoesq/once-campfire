class Rooms::ArchivedController < ApplicationController
  before_action :ensure_administrator

  # Lists the account's archived channels so an administrator can review and
  # unarchive them. Directs are never archivable, so only channels appear here.
  def index
    @rooms = Room.without_directs.archived.ordered
  end

  private
    def ensure_administrator
      head :forbidden unless Current.user.administrator?
    end
end
