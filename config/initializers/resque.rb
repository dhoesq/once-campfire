# frozen_string_literal: true

# Point Resque (and the ActiveJob :resque adapter) at the same Redis the rest of
# the app uses. Without this, Resque defaults to redis://localhost:6379, which
# does not exist in this deployment, so every job enqueue (e.g. Room::PushMessageJob
# fired when a message is posted) raises Redis::CannotConnectError and 500s the
# request that triggered it. See config/cable.yml and config/environments/production.rb
# which already read REDIS_URL.
require "resque"

Resque.redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
