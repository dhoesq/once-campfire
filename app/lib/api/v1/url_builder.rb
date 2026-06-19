# ============================================================
# F-023a -- absolute URL helper for serializers
# ============================================================
# Serializers run inside an API request (Current.request is set by
# SetCurrentRequest), so we build absolute URLs the same way the web UI does:
# Rails route helpers + the current request host/protocol.
#
# We reuse the EXACT same routes the web UI uses:
#   - fresh_user_avatar_url  (config/routes.rb `direct :fresh_user_avatar`)
#   - rails_blob_url         (Active Storage) for attachments
# so URLs are identical to what the app already serves -- no hand-rolled paths.
module Api
  module V1
    module UrlBuilder
      module_function

      def url_helpers
        Rails.application.routes.url_helpers
      end

      # host/protocol from the current request (set by SetCurrentRequest into
      # Current.request). Falls back to ENV-provided defaults if absent so
      # background/edge contexts don't raise.
      def url_options
        host = Current.respond_to?(:request_host) ? Current.request_host : nil
        protocol = Current.respond_to?(:request_protocol) ? Current.request_protocol : nil
        opts = {}
        opts[:host] = host if host.present?
        opts[:protocol] = protocol if protocol.present?
        if opts[:host].blank?
          # Last-resort default so URL generation never raises in odd contexts.
          default = ENV["CAMPFIRE_HOST"] || Rails.application.config.action_controller.default_url_options&.dig(:host)
          opts[:host] = default if default.present?
        end
        opts
      end

      def fresh_user_avatar_url(user)
        url_helpers.fresh_user_avatar_url(user, **url_options)
      end

      def rails_blob_url(blob)
        url_helpers.rails_blob_url(blob, **url_options)
      end

      # Absolute URL for an Active Storage variant/representation (thumbnails).
      def rails_representation_url(representation)
        url_helpers.rails_representation_url(representation, **url_options)
      end
    end
  end
end
