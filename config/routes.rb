Rails.application.routes.draw do
  root "welcome#show"

  # ── Mission Control API (F-023a/b/c) ────────────────────────
  # A NEW parallel JSON surface. Paths are RELATIVE to /api/v1 so that MC's
  # CAMPFIRE_API_URL (which already includes /api/v1) maps directly:
  #   GET    /api/v1/me
  #   GET    /api/v1/rooms
  #   GET    /api/v1/rooms/:room_id/messages
  #   POST   /api/v1/rooms/:room_id/messages
  #   PATCH  /api/v1/messages/:id
  #   DELETE /api/v1/messages/:id
  #   POST   /api/v1/dms
  #   GET    /api/v1/users
  #   GET    /api/v1/search
  # Realtime gateway (plain-JSON WebSocket): GET /api/v1/ws
  namespace :api do
    namespace :v1 do
      get  "me",     to: "me#show"
      get  "rooms",  to: "rooms#index"

      get  "rooms/:room_id/messages", to: "messages#index"
      post "rooms/:room_id/messages", to: "messages#create"

      patch  "messages/:id", to: "messages#update"
      delete "messages/:id", to: "messages#destroy"

      post "dms",    to: "dms#create"
      get  "users",  to: "users#index"
      get  "search", to: "searches#index"

      # Plain-JSON WebSocket realtime gateway (Rack endpoint).
      mount Api::V1::WsGateway, at: "ws"
    end
  end

  resource :first_run

  resource :session do
    scope module: "sessions" do
      resources :transfers, only: %i[ show update ]
    end
  end

  resource :account do
    scope module: "accounts" do
      resources :users

      resources :bots do
        scope module: "bots" do
          resource :key, only: :update
        end
      end

      resource :join_code, only: :create
      resource :logo, only: %i[ show destroy ]
      resource :custom_styles, only: %i[ edit update ]
    end
  end

  direct :fresh_account_logo do |options|
    route_for :account_logo, v: Current.account&.updated_at&.to_fs(:number), size: options[:size]
  end

  get "join/:join_code", to: "users#new", as: :join
  post "join/:join_code", to: "users#create"

  resources :qr_code, only: :show

  resources :users, only: :show do
    scope module: "users" do
      resource :avatar, only: %i[ show destroy ]
      resource :ban, only: %i[ create destroy ]

      scope defaults: { user_id: "me" } do
        resource :sidebar, only: :show
        resource :profile
        resources :push_subscriptions do
          scope module: "push_subscriptions" do
            resources :test_notifications, only: :create
          end
        end
      end
    end
  end

  namespace :autocompletable do
    resources :users, only: :index
  end

  direct :fresh_user_avatar do |user, options|
    route_for :user_avatar, user.avatar_token, v: user.updated_at.to_fs(:number)
  end

  resources :rooms do
    resources :messages do
      member do
        # Thread panel for a root message (root + replies + thread composer).
        get :thread
      end
    end

    post ":bot_key/messages", to: "messages/by_bots#create", as: :bot_messages

    scope module: "rooms" do
      resource :refresh, only: :show
      resource :settings, only: :show
      resource :involvement, only: %i[ show update ]
      resource :star, only: %i[ create destroy ]
      resource :read, only: :update
      resource :archive, only: %i[ create destroy ]
    end

    get "@:message_id", to: "rooms#show", as: :at_message
  end

  namespace :rooms do
    resources :opens
    resources :closeds
    resources :directs
    resources :archived, only: :index, as: :archived_index
  end

  resources :messages do
    scope module: "messages" do
      resources :boosts
      resource :pin, only: %i[ create destroy ]
      resource :bookmark, only: %i[ create destroy ]
      resource :forward, only: %i[ new create ]
    end
  end

  resources :searches, only: %i[ index create ] do
    delete :clear, on: :collection
  end

  # Full-page lists of the current user's saved messages and @mentions.
  resources :bookmarks, only: :index
  resource :mentions, only: :show

  # Scheduled send (compose now, post later) and personal reminders. Create from
  # the composer / message action menu; index is the management list; destroy
  # cancels. All scoped to Current.user in the controllers.
  resources :scheduled_messages, only: %i[ index create destroy ]
  resources :reminders, only: %i[ index create destroy ]

  resource :unfurl_link, only: :create

  # Mark all rooms read for the current user (distinct from the per-room
  # rooms/:room_id/read resource above).
  resource :reads, only: :update

  # Machine-triggered disaster-recovery backup. Token-authenticated (see
  # BackupsController), not behind the session login scope. Only enqueues a job.
  resource :backups, only: :create

  get "webmanifest"    => "pwa#manifest"
  get "service-worker" => "pwa#service_worker"

  get "up" => "rails/health#show", as: :rails_health_check
end
