# ============================================================
# F-023c -- API base controller: assertion auth + scoping
# ============================================================
# A NEW parallel surface. It deliberately does NOT inherit the web app's
# cookie/session authentication (ApplicationController + Authentication concern).
# It is a token API: every request carries a signed X-MC-Assertion header
# (F-024 wire format) which we verify, dedupe (replay), and resolve to an
# ACTIVE Campfire user. No cookies, no CSRF, no Turbo.
#
# Inert-when-unconfigured: if MC_API_SECRET is unset, AssertionVerifier fails
# closed and every request is 401. Nothing else in the app is affected.
module Api
  module V1
    class BaseController < ActionController::API
      ASSERTION_HEADER = "X-MC-Assertion".freeze
      SERVICE_HEADER = "X-MC-Service".freeze

      before_action :set_current_request
      before_action :authenticate_assertion!
      after_action :audit_log

      # Any uncaught error becomes a clean 502 -- the API must never 500 on a
      # bad row or unexpected upstream condition.
      rescue_from StandardError, with: :handle_unexpected_error

      private

      # URL helpers in serializers read Current.request_host/protocol.
      def set_current_request
        Current.request = request
      end

      def authenticate_assertion!
        token = request.headers[ASSERTION_HEADER]
        payload = Api::V1::AssertionVerifier.verify(token)
        return unauthorized! if payload.nil?

        # Replay defense: reject a jti seen within its remaining validity window.
        return unauthorized! if replayed?(payload)

        user = User.active.find_by(email_address: payload[:email])
        return unauthorized! if user.nil?

        Current.user = user
        @assertion_payload = payload
      end

      # Rails.cache-backed jti dedupe. Production cache_store is redis_cache_store
      # (shared + persistent across web/worker processes), so this dedupes
      # cluster-wide. cache.write(unless_exist: true) is an atomic "set if not
      # present"; if it returns false the jti was already seen -> replay.
      #
      # TTL = remaining lifetime of the assertion (exp - now), so the key expires
      # exactly when replay is no longer possible anyway. Floor at 1s.
      #
      # NOTE: if the cache store is ever swapped to a non-shared store
      # (:memory_store, :null_store) this dedupe degrades to per-process / no-op.
      # In production it is Redis, so this holds. We do NOT add a gem.
      def replayed?(payload)
        ttl = payload[:exp] - Time.now.to_i
        ttl = 1 if ttl < 1
        key = "api:v1:jti:#{payload[:jti]}"
        # write returns true if it actually wrote (jti unseen), false if present.
        stored = Rails.cache.write(key, true, unless_exist: true, expires_in: ttl)
        !stored
      rescue => e
        # If the cache is unavailable, fail OPEN on dedupe (auth + exp still
        # protect us) rather than locking everyone out. Logged for visibility.
        Rails.logger.warn("[api/v1] jti dedupe unavailable: #{e.class} #{e.message}")
        false
      end

      def unauthorized!
        head :unauthorized
      end

      # 404 (not 403) for non-members so room existence is not leaked (no IDOR
      # oracle). Returns the membership when the caller is a member.
      def require_member!(room_id)
        membership = Current.user.memberships.find_by(room_id: room_id)
        not_found! if membership.nil?
        membership
      end

      def not_found!
        render(json: { error: "not_found" }, status: :not_found) && (return nil)
      end

      def current_user
        Current.user
      end

      # Lightweight per-request audit line (user email, method, path, room id).
      # A DB table was considered and rejected for v1 to avoid migration risk.
      def audit_log
        return if Current.user.nil?
        Rails.logger.info(
          "[api/v1/audit] user=#{Current.user.email_address} " \
          "method=#{request.request_method} path=#{request.path} " \
          "room=#{params[:room_id] || params[:id] || '-'} " \
          "service=#{request.headers[SERVICE_HEADER] || '-'} " \
          "status=#{response.status}"
        )
      rescue => e
        Rails.logger.warn("[api/v1] audit_log failed: #{e.class} #{e.message}")
      end

      def handle_unexpected_error(error)
        Rails.logger.error("[api/v1] unexpected error: #{error.class} #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}")
        render json: { error: "upstream_error" }, status: :bad_gateway
      end

      # --- shared param helpers ---

      # Clamp limit to [1, 100]; default 50 when absent/non-numeric. Mirrors MC's
      # own clamp in chat.ts (Math.min(100, Math.max(1, floor(n)))).
      def clamped_limit(default: 50)
        raw = params[:limit].to_s
        return default unless raw.match?(/\A\d+\z/)
        n = raw.to_i
        return default if n <= 0
        [[n, 1].max, 100].min
      end
    end
  end
end
