class Messages::BookmarksController < ApplicationController
  before_action :set_message

  # Toggle: saving an already-saved message removes it. The per-message action
  # menu lives inside the fragment-cached _message partial, which is keyed on the
  # message alone (not the user), so the menu cannot reflect per-user saved
  # state. A single idempotent toggle keeps the menu correct for everyone while
  # the Saved page (uncached) is where a message is explicitly unsaved.
  def create
    bookmark = Current.user.bookmarks.find_by(message: @message)

    if bookmark
      bookmark.destroy
    else
      # find_or_create_by + rescue makes a fast double-tap idempotent rather than
      # 500ing on the unique [user_id, message_id] index.
      begin
        Current.user.bookmarks.find_or_create_by(message: @message)
      rescue ActiveRecord::RecordNotUnique
        # Already saved by a racing request; the desired end state holds.
      end
    end

    head :no_content
  end

  def destroy
    Current.user.bookmarks.where(message: @message).destroy_all

    respond_to do |format|
      # Used by the Saved page Unsave control: drop the row in place.
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(
          ActionView::RecordIdentifier.dom_id(@message, :bookmark_row)
        )
      end
      format.html { head :no_content }
    end
  end

  private
    def set_message
      @message = Current.user.reachable_messages.find(params[:message_id])
    end
end
