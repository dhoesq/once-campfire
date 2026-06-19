class SearchesController < ApplicationController
  before_action :set_messages

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

    def query
      params[:q]&.gsub(/[^[:word:]]/, " ")
    end
end
