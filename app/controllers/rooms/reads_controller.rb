class Rooms::ReadsController < ApplicationController
  include RoomScoped, SidebarRendering

  # Mark the room unread for the current user starting at a chosen message.
  # The read model is room-level (a single unread_at timestamp per membership),
  # so we set unread_at to the selected message's created_at: the room then
  # reads as unread in the sidebar. See report for the divider limitation.
  def update
    message = @room.messages.find(params[:message_id])
    @membership.update!(unread_at: message.created_at)

    broadcast_unread
    rerender_sidebar
  end

  private
    def broadcast_unread
      ActionCable.server.broadcast "unread_rooms", { roomId: @room.id }
    end

    def rerender_sidebar
      assign_sidebar_memberships

      sidebar_html = render_to_string(partial: "users/sidebars/sidebar_frame")

      Turbo::StreamsChannel.broadcast_replace_to Current.user, :rooms,
        target: "user_sidebar", html: sidebar_html

      render turbo_stream: turbo_stream.replace("user_sidebar", sidebar_html)
    end
end
