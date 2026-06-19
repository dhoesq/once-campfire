class BookmarksController < ApplicationController
  def index
    # Saved messages for the current user, newest-saved first. Bookmarks already
    # belong to the user; we additionally constrain to rooms the user can still
    # reach so a bookmark left behind after losing access never leaks. Eager-load
    # the same associations rooms#show uses to avoid N+1 while rendering.
    @messages = Current.user.bookmarked_messages
      .where(room_id: Current.user.rooms)
      .with_creator.with_attachment_details.with_boosts
      .order("bookmarks.created_at desc")
      .limit(100)
  end
end
