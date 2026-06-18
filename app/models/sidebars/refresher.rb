# Re-renders a user's sidebar and pushes it to their personal :rooms Turbo
# Stream so the unread-count badges update live. Mirrors the replace that
# Rooms::StarsController / Rooms::ReadsController perform in-request: same
# partial ("users/sidebars/sidebar_frame"), same stream (the user's :rooms),
# same target ("user_sidebar"). Used from the background message-receive path,
# where there is no request and Current.user must be set explicitly.
class Sidebars::Refresher
  def self.refresh(user)
    new(user).refresh
  end

  def initialize(user)
    @user = user
  end

  def refresh
    html = render_sidebar
    Turbo::StreamsChannel.broadcast_replace_to @user, :rooms, target: "user_sidebar", html: html
  end

  private
    def render_sidebar
      # The sidebar partial reads Current.user/Current.account; set the acting
      # user for the duration of the render. Current.account is derived
      # (Account.first), so only the user needs setting.
      Current.set(user: @user) do
        ApplicationController.render(
          partial: "users/sidebars/sidebar_frame",
          assigns: Sidebars::Data.for(@user)
        )
      end
    end
end
