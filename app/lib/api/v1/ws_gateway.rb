# ============================================================
# F-023b -- plain-JSON WebSocket realtime gateway (Rack endpoint)
# ============================================================
# Mounted at /api/v1/ws. A gem-free plain-JSON WebSocket built on the
# already-locked `websocket-driver` (ships with actioncable) plus a raw Redis
# pub/sub consumer. This is NOT ActionCable -- the wire is bare JSON to match
# the MC client (frontend/src/lib/campfireSocket.ts):
#
#   client -> {"action":"subscribe","room_id":"123"}
#   client -> {"action":"unsubscribe","room_id":"123"}
#   server -> {"type":"message.created", ...}   (bare event JSON, no envelope)
#
# Auth: the assertion can't be sent as a header from a browser WS, so it is
# read from the ?assertion= query param (the MC backend is the client and can
# always set it). Same AssertionVerifier as REST. On bad/absent assertion we
# accept the upgrade then immediately close with 4001 (policy violation) so the
# client gets a clean signal rather than a raw TCP reset.
#
# Per connection:
#   - one websocket-driver bound to the hijacked socket
#   - a reader thread pumping inbound bytes into the driver
#   - one Redis subscriber thread PER subscribed room (api:v1:room:<id>),
#     forwarding every published event as a raw text frame
#
# Membership is enforced on subscribe (404-equivalent: the subscribe is just
# ignored if the user is not a member, no room is leaked).
require "websocket/driver"

module Api
  module V1
    class WsGateway
      CLOSE_POLICY = 4001 # auth failure / policy violation

      # WebSocket::Driver.rack expects a socket-like object exposing #env, #url,
      # and #write -- NOT the raw rack env Hash. Passing the Hash raised
      # "NoMethodError undefined method 'env' for an instance of Hash" on every
      # connection. This adapter wraps the env + the hijacked IO.
      class SocketAdapter
        attr_reader :env, :url

        def initialize(env, io)
          @env = env
          @io = io
          scheme = env["rack.url_scheme"] == "https" ? "wss" : "ws"
          host = env["HTTP_HOST"] || "localhost"
          path = env["REQUEST_URI"] ||
                 [ env["PATH_INFO"], env["QUERY_STRING"] ].reject { |s| s.to_s.empty? }.join("?")
          @url = "#{scheme}://#{host}#{path}"
        end

        def write(data)
          @io.write(data)
        rescue StandardError
          nil
        end
      end

      def self.call(env)
        new(env).call
      end

      def initialize(env)
        @env = env
        @request = ActionDispatch::Request.new(env)
        @subscribers = {}      # room_id(String) => Thread
        @subscriber_redis = {} # room_id(String) => Redis (so we can unsubscribe/close)
        @mutex = Mutex.new
        @open = false
      end

      def call
        unless WebSocket::Driver.websocket?(@env)
          return [ 426, { "Content-Type" => "text/plain" }, [ "Upgrade Required" ] ]
        end

        @io = hijack_io
        return not_supported unless @io

        @socket = SocketAdapter.new(@env, @io)
        @driver = WebSocket::Driver.rack(@socket)
        wire_driver_callbacks

        @driver.start
        start_reader

        # Async response: we own the socket now.
        [ -1, {}, [] ]
      rescue => e
        Rails.logger.error("[api/v1/ws] gateway error: #{e.class} #{e.message}")
        [ 500, { "Content-Type" => "text/plain" }, [ "ws error" ] ]
      end

      private

      def hijack_io
        if @env["rack.hijack"]
          @env["rack.hijack"].call
          @env["rack.hijack_io"]
        end
      end

      def not_supported
        [ 501, { "Content-Type" => "text/plain" }, [ "hijack not supported" ] ]
      end

      def wire_driver_callbacks
        @driver.on(:open) do
          @open = true
          # Authenticate now. If invalid, close with the policy code.
          unless authenticate
            close_with(CLOSE_POLICY, "unauthorized")
          end
        end

        @driver.on(:message) { |event| handle_message(event.data) }

        @driver.on(:close) do
          @open = false
          teardown
        end

        @driver.on(:error) do |event|
          Rails.logger.warn("[api/v1/ws] driver error: #{event.message}")
        end
      end

      # Verify the ?assertion= query param into a Campfire user. Sets @user.
      def authenticate
        token = @request.params["assertion"]
        payload = Api::V1::AssertionVerifier.verify(token)
        return false if payload.nil?
        @user = User.active.find_by(email_address: payload[:email])
        !@user.nil?
      rescue => e
        Rails.logger.warn("[api/v1/ws] auth failed: #{e.class} #{e.message}")
        false
      end

      def handle_message(data)
        return unless @user # ignore frames before auth resolves
        frame = JSON.parse(data)
        return unless frame.is_a?(Hash)

        case frame["action"]
        when "subscribe"   then subscribe(frame["room_id"].to_s)
        when "unsubscribe" then unsubscribe(frame["room_id"].to_s)
        end
      rescue JSON::ParserError
        # ignore malformed frames (mirrors campfireSocket.ts tolerance)
      rescue => e
        Rails.logger.warn("[api/v1/ws] handle_message failed: #{e.class} #{e.message}")
      end

      # Member-scoped subscribe. Silently ignored for non-members (no room
      # existence leak). Starts one Redis subscriber thread for the room.
      def subscribe(room_id)
        return if room_id.empty?
        return if @subscribers.key?(room_id)
        return unless member?(room_id)

        redis = Redis.new(url: Api::V1::Realtime.redis_url)
        @mutex.synchronize { @subscriber_redis[room_id] = redis }

        thread = Thread.new do
          begin
            redis.subscribe(Api::V1::Realtime.channel_for(room_id)) do |on|
              on.message do |_channel, payload|
                # payload is already the bare event JSON string -- forward as-is.
                send_text(payload)
              end
            end
          rescue => e
            Rails.logger.warn("[api/v1/ws] subscriber thread for room #{room_id} ended: #{e.class} #{e.message}")
          end
        end
        @mutex.synchronize { @subscribers[room_id] = thread }
      end

      def unsubscribe(room_id)
        return if room_id.empty?
        stop_room(room_id)
      end

      def member?(room_id)
        @user.memberships.exists?(room_id: room_id)
      rescue => e
        Rails.logger.warn("[api/v1/ws] member? check failed: #{e.class} #{e.message}")
        false
      end

      def start_reader
        @reader = Thread.new do
          begin
            loop do
              data = @io.readpartial(4096)
              @driver.parse(data)
            end
          rescue EOFError, IOError, Errno::ECONNRESET, Errno::EPIPE
            # client disconnected
          rescue => e
            Rails.logger.warn("[api/v1/ws] reader thread error: #{e.class} #{e.message}")
          ensure
            teardown
          end
        end
      end

      def send_text(str)
        @driver.text(str) if @open
      rescue => e
        Rails.logger.warn("[api/v1/ws] send failed: #{e.class} #{e.message}")
      end

      def close_with(code, reason)
        @driver.close(reason, code)
      rescue
        teardown
      end

      def stop_room(room_id)
        redis = nil
        thread = nil
        @mutex.synchronize do
          redis = @subscriber_redis.delete(room_id)
          thread = @subscribers.delete(room_id)
        end
        # unsubscribe wakes the blocking subscribe loop; then close + kill.
        begin
          redis&.unsubscribe(Api::V1::Realtime.channel_for(room_id))
        rescue
        end
        begin
          redis&.close
        rescue
        end
        thread&.kill if thread&.alive?
      end

      # Tear down every room subscription + socket exactly once.
      def teardown
        return if @torn_down
        @torn_down = true
        room_ids = @mutex.synchronize { @subscribers.keys.dup }
        room_ids.each { |rid| stop_room(rid) }
        begin
          @io&.close
        rescue
        end
      end
    end
  end
end
