class RoomsController < ApplicationController
  before_action :set_room, only: %i[ show destroy ]
  before_action :ensure_can_administer, only: %i[ destroy ]
  before_action :remember_last_room_visited, only: :show

  def index
    redirect_to room_url(Current.user.rooms.last)
  end

  def show
    # The viewer's membership carries unread_at, which the message list uses to
    # place the "New messages" divider. Read here at open time, before the
    # presence subscription marks the room read (unread_at: nil).
    @membership = Current.user.memberships.find_by(room_id: @room.id)
    @messages = find_messages
  end

  def destroy
    @room.destroy

    broadcast_remove_room
    redirect_to root_url
  end

  private
    def set_room
      if room = Current.user.rooms.find_by(id: params[:room_id] || params[:id])
        @room = room
      else
        redirect_to root_url, alert: "Room not found or inaccessible"
      end
    end

    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?(@room)
    end

    def ensure_permission_to_create_rooms
      if Current.account.settings.restrict_room_creation_to_administrators? && !Current.user.administrator?
        head :forbidden
      end
    end

    def find_messages
      # Main timeline shows ROOT messages only; thread replies live in the
      # thread panel. Filtering to .roots here keeps replies out of the initial
      # room render and of the permalink page_around. A permalink that targets a
      # reply (not a root) falls back to the latest page since the reply is not
      # part of the main timeline.
      messages = @room.messages.roots.with_creator.with_attachment_details.with_boosts

      if show_first_message = messages.find_by(id: params[:message_id])
        @messages = messages.page_around(show_first_message)
      else
        @messages = messages.last_page
      end
    end

    def room_params
      params.require(:room).permit(:name)
    end

    def broadcast_remove_room
      broadcast_remove_to :rooms, target: [ @room, :list ]
    end
end
