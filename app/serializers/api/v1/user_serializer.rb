# ============================================================
# F-023a -- UserSerializer (types.ts CampfireUser / MessageAuthor)
# ============================================================
# CampfireUser: { id: string, name, email?, avatar_url: string | null }
#   - email present on GET /me + GET /users, omitted on embedded message authors
# MessageAuthor: { id: string, name, avatar_url: string | null } (no email)
#
# All Campfire integer ids are serialized as STRINGS (.to_s) -- types.ts ids
# are TS `string`.
module Api
  module V1
    class UserSerializer
      def initialize(user, include_email: true)
        @user = user
        @include_email = include_email
      end

      # Full CampfireUser (with email) -- for /me and /users.
      def as_json(*)
        h = author_json
        h[:email] = @user.email_address if @include_email
        h
      end

      # MessageAuthor (no email) -- embedded in a Message.
      def author_json
        {
          id: @user.id.to_s,
          name: @user.name,
          avatar_url: avatar_url
        }
      end

      private

      # Absolute avatar URL via the app's existing fresh_user_avatar route
      # (config/routes.rb `direct :fresh_user_avatar`). Returns nil if the URL
      # can't be built (e.g. missing host) rather than raising.
      def avatar_url
        Api::V1::UrlBuilder.fresh_user_avatar_url(@user)
      rescue => e
        Rails.logger.warn("[api/v1] avatar_url failed for user #{@user.id}: #{e.class} #{e.message}")
        nil
      end
    end
  end
end
