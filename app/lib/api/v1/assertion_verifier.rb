# ============================================================
# F-023c — Mission Control signed-assertion verifier
# ============================================================
# Port of Mission Control's reference verifier
# (prototype/backend/src/services/campfire/auth.ts -> verifyAssertion).
#
# Wire format (locked contract):
#   token = base64url(payloadJson) "." base64url(HMAC-SHA256(secret, encodedPayload))
#   header: X-MC-Assertion: <token>
#
# Payload claims: { email, name?, iat, exp, jti }  (see types.ts AssertionPayload)
#
# This object is PURE + deterministic given (token, secret, now). It does the
# cryptographic + claim validation only. Replay dedupe (jti) is layered on top
# by Api::V1::BaseController because it needs Rails.cache, which is impure.
#
# The shared secret comes from ENV["MC_API_SECRET"] and MUST equal Mission
# Control's CAMPFIRE_API_SECRET, byte-for-byte. If unset, every verification
# fails closed (returns nil), so the API is inert until configured.
module Api
  module V1
    class AssertionVerifier
      # Returns the decoded payload Hash (symbol keys :email, :name, :iat,
      # :exp, :jti) on success, or nil on ANY failure. Never raises on bad
      # input -- mirrors the TS reference verifier which "never throws".
      #
      # now: injectable Unix-seconds clock for deterministic tests.
      def self.verify(token, secret: ENV["MC_API_SECRET"], now: nil)
        new(secret: secret, now: now).verify(token)
      end

      def initialize(secret: ENV["MC_API_SECRET"], now: nil)
        @secret = secret
        @now = now
      end

      def verify(token)
        return nil if @secret.nil? || @secret.empty?
        return nil unless token.is_a?(String)

        # Split on the FIRST '.' only. Mirrors token.indexOf('.') in auth.ts.
        dot = token.index(".")
        return nil if dot.nil? || dot <= 0 || dot == token.length - 1

        encoded_payload = token[0...dot]
        provided_sig = token[(dot + 1)..-1]

        # Recompute the signature over the encoded payload and compare in
        # constant time. expected_sig is base64url(raw HMAC bytes), matching
        # base64url(hmac(secret, encodedPayload)) on the MC side.
        expected_sig = base64url_encode(hmac(encoded_payload))
        return nil unless secure_compare(provided_sig, expected_sig)

        # Signature valid -- decode + parse the claims.
        payload = decode_payload(encoded_payload)
        return nil if payload.nil?

        # Type validation mirrors auth.ts:
        #   email String, iat Numeric, exp Numeric, jti String.
        return nil unless payload[:email].is_a?(String)
        return nil unless payload[:iat].is_a?(Numeric)
        return nil unless payload[:exp].is_a?(Numeric)
        return nil unless payload[:jti].is_a?(String)

        # Expiry: reject when now >= exp (same >= as the TS verifier).
        ts = @now || Time.now.to_i
        return nil if ts >= payload[:exp]

        payload
      end

      private

      def hmac(data)
        OpenSSL::HMAC.digest(OpenSSL::Digest.new("SHA256"), @secret, data)
      end

      # base64url WITHOUT padding -- matches Node's Buffer.toString('base64url').
      def base64url_encode(bytes)
        Base64.urlsafe_encode64(bytes, padding: false)
      end

      # Decode a base64url string back to bytes. Node's
      # Buffer.from(str, 'base64url') tolerates missing padding; Ruby's
      # urlsafe_decode64 is strict about padding, so re-pad first.
      def base64url_decode(str)
        padded = str.tr("-_", "+/")
        padded += "=" * ((4 - padded.length % 4) % 4)
        Base64.strict_decode64(padded)
      rescue ArgumentError
        nil
      end

      def decode_payload(encoded_payload)
        json = base64url_decode(encoded_payload)
        return nil if json.nil?
        parsed = JSON.parse(json, symbolize_names: true)
        return nil unless parsed.is_a?(Hash)
        parsed
      rescue JSON::ParserError
        nil
      end

      # Constant-time string compare. Length-guard then the AS helper, mirroring
      # the TS buffersEqual (length-guard then timingSafeEqual).
      def secure_compare(a, b)
        return false unless a.is_a?(String) && b.is_a?(String)
        ActiveSupport::SecurityUtils.secure_compare(a, b)
      end
    end
  end
end
