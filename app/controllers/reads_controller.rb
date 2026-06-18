class ReadsController < ApplicationController
  include SidebarRendering

  # Mark every room read for the current user. Operates only on the current
  # user's own memberships (no room param, no other user can be touched), then
  # re-renders + broadcasts their sidebar so unread badges/bold/counts clear
  # live. Mirrors the in-request replace + :rooms broadcast that
  # Rooms::ReadsController and Rooms::StarsController perform.
  def update
    Current.user.memberships.unread.update_all(unread_at: nil)

    rerender_sidebar
  end

  private
    def rerender_sidebar
      assign_sidebar_memberships

      sidebar_html = render_to_string(partial: "users/sidebars/sidebar_frame")

      Turbo::StreamsChannel.broadcast_replace_to Current.user, :rooms,
        target: "user_sidebar", html: sidebar_html

      render turbo_stream: turbo_stream.replace("user_sidebar", sidebar_html)
    end
end
