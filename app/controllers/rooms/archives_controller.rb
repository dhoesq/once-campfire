class Rooms::ArchivesController < RoomsController
  before_action :set_room
  before_action :ensure_can_administer
  before_action :ensure_archivable

  # Archive the channel: freeze it read-only and remove it from members' active
  # sidebars. Directs are blocked by ensure_archivable.
  def create
    @room.archive

    broadcast_remove_room
    redirect_to room_url(@room)
  end

  # Unarchive the channel: clear archived_at and return it to members' sidebars
  # via the normal shared-room broadcast.
  def destroy
    @room.unarchive

    broadcast_restore_room
    redirect_to room_url(@room)
  end

  private
    def ensure_archivable
      head :forbidden unless @room.archivable?
    end

    # Remove the room row from every member's sidebar (acting tab + all other
    # clients). Removing a DOM id that a non-member never had is a harmless no-op,
    # so the shared :rooms stream is safe here for both Open and Closed rooms.
    def broadcast_remove_room
      broadcast_remove_to :rooms, target: [ @room, :list ]
    end

    # Prepend the room row back into each member's Channels list. Scoped per
    # member (not the global :rooms stream) so a Closed room never leaks into a
    # non-member's sidebar. Mirrors Rooms::ClosedsController#broadcast_create_room.
    def broadcast_restore_room
      html = render_to_string(partial: "users/sidebars/rooms/shared", locals: { room: @room })

      @room.users.each do |user|
        broadcast_prepend_to user, :rooms, target: :shared_rooms, html: html
      end
    end
end
