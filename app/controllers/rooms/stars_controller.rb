class Rooms::StarsController < ApplicationController
  include RoomScoped, SidebarRendering

  def create
    @membership.star
    rerender_sidebar
  end

  def destroy
    @membership.unstar
    rerender_sidebar
  end

  private
    # Re-render the whole sidebar so starred items move into/out of the Starred
    # section. The acting tab gets the turbo stream in the HTTP response; other
    # tabs/clients get the same stream via the user's :rooms broadcast stream.
    def rerender_sidebar
      assign_sidebar_memberships

      sidebar_html = render_to_string(partial: "users/sidebars/sidebar_frame")

      Turbo::StreamsChannel.broadcast_replace_to Current.user, :rooms,
        target: "user_sidebar", html: sidebar_html

      render turbo_stream: turbo_stream.replace("user_sidebar", sidebar_html)
    end
end
