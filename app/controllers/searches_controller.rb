class SearchesController < ApplicationController
  # Cap on how many room (channel + DM) hits we show above the message results.
  ROOM_RESULTS_LIMIT = 10

  before_action :set_messages
  before_action :set_rooms

  def index
    @query = query if query.present?
    @recent_searches = Current.user.searches.ordered
    @return_to_room = last_room_visited

    respond_to do |format|
      format.html
      # Lightweight results-only fragment for the sidebar inline search. Reuses
      # the exact same @messages set built by set_messages (the user-scoped
      # reachable_messages.search), so there is no second query path and no
      # broadened access. Rendered server-side via searches/_results, so result
      # text is HTML-escaped by ERB (no client innerHTML of raw message text).
      format.json { render partial: "searches/results", formats: [ :html ], layout: false }
    end
  end

  def create
    Current.user.searches.record(query)
    redirect_to searches_url(q: query)
  end

  def clear
    Current.user.searches.destroy_all
    redirect_to searches_url
  end

  private
    def set_messages
      if query.present?
        @messages = Current.user.reachable_messages.search(query).last(100)
      else
        @messages = Message.none
      end
    end

    # Channels (by name) and DMs (by another participant's name) the current user
    # belongs to, matched against the search term and surfaced above message hits.
    #
    # Strictly scoped to Current.user.rooms (through memberships), so this only
    # ever returns rooms the user is already a member of. Membership includes
    # rooms whose involvement is "invisible" (a hidden room is still a membership
    # row), so those stay findable. Archived channels are excluded.
    #
    # Computed in a before_action so it runs for BOTH the html (full-page) and
    # json (inline sidebar) paths off the same logic.
    def set_rooms
      term = room_search_term

      if term.present?
        @rooms = (matched_channels(term) + matched_direct_rooms(term)).first(ROOM_RESULTS_LIMIT)
      else
        @rooms = []
      end
    end

    # Channels (non-direct rooms): case-insensitive name LIKE, parameterized.
    # `.active` excludes archived channels (archived_at: nil). `.without_directs`
    # keeps this to named channels only; DMs are handled separately.
    def matched_channels(term)
      Current.user.rooms.active.without_directs
        .where("lower(rooms.name) LIKE ?", "%#{term.downcase}%")
        .ordered
        .to_a
    end

    # DMs (direct rooms have no name): match when any OTHER participant's name
    # contains the term (case-insensitive). Directs are never archivable, so no
    # archived filter is needed, but we still scope to the user's own rooms.
    # Users are preloaded to avoid per-room queries; the user's direct-room count
    # is bounded in practice.
    def matched_direct_rooms(term)
      needle = term.downcase

      Current.user.rooms.directs.includes(:users).select do |room|
        room.users.any? do |user|
          user != Current.user && user.name.to_s.downcase.include?(needle)
        end
      end
    end

    # FTS term for message-body matching: strips non-word chars (SQLite FTS5).
    def query
      params[:q]&.gsub(/[^[:word:]]/, " ")
    end

    # Term for room-name LIKE matching. Kept separate from `query` so the FTS
    # sanitization (which can blank out names like "mission-control-feed") does
    # not strip the characters we need. Lightly trimmed; always bound as a SQL
    # parameter by the callers above (never interpolated into SQL).
    def room_search_term
      params[:q]&.strip
    end
end
