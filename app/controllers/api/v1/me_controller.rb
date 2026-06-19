# F-023a -- GET /api/v1/me
module Api
  module V1
    class MeController < BaseController
      def show
        render json: Api::V1::UserSerializer.new(current_user, include_email: true).as_json
      end
    end
  end
end
