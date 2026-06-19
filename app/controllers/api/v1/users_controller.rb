# F-023a -- GET /api/v1/users : directory the caller can see.
# Web UI scoping: the autocomplete/directory shows ACTIVE users. We match that
# (active, name-ordered). Email is included (full CampfireUser) so MC can map
# its users to Campfire users for DMs.
module Api
  module V1
    class UsersController < BaseController
      def index
        users = User.active.ordered
        render json: users.map { |u| Api::V1::UserSerializer.new(u, include_email: true).as_json }
      end
    end
  end
end
