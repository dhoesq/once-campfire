# F-023a -- POST /api/v1/dms  body: { user_id }
# Find-or-create the singleton direct room between the caller and the target
# user, using the model's real finder Rooms::Direct.find_or_create_for([..]).
module Api
  module V1
    class DmsController < BaseController
      def create
        user_id = params[:user_id]
        return render(json: { error: "user_id_required" }, status: :unprocessable_entity) if user_id.blank?

        other = User.active.find_by(id: user_id)
        return not_found! if other.nil?

        room = Rooms::Direct.find_or_create_for([ current_user, other ])
        membership = current_user.memberships.find_by(room_id: room.id)

        render json: Api::V1::RoomSerializer.new(room, membership: membership, current_user: current_user).as_json
      end
    end
  end
end
