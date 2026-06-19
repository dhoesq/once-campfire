class MentionsController < ApplicationController
  # Mentions are not stored in their own table. The source of truth is
  # Message#mentionees, which parses the ActionText body for attached users
  # (body.body.attachables.grep(User)) and intersects with the room's members.
  #
  # We scan a recent window of the user's reachable_messages with rich-text
  # bodies eager-loaded, then keep those whose body attaches the current user.
  # Because reachable_messages already guarantees room membership, an attached
  # user is necessarily a member, so checking the loaded body avoids the
  # per-message membership query mentionees would otherwise run (no N+1).
  MENTION_SCAN_WINDOW = 500
  MENTION_LIMIT = 100

  def show
    candidates = Current.user.reachable_messages
      .with_creator.with_attachment_details.with_boosts
      .ordered.last(MENTION_SCAN_WINDOW)

    @messages = candidates
      .select { |message| mentions_current_user?(message) }
      .last(MENTION_LIMIT)
      .reverse
  end

  private
    def mentions_current_user?(message)
      return false unless message.body.body

      message.body.body.attachables.grep(User).any? { |user| user.id == Current.user.id }
    end
end
