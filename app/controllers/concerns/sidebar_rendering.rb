module SidebarRendering
  extend ActiveSupport::Concern

  private
    # Computes the membership groups + unread counts the sidebar renders and
    # assigns them as the instance variables the sidebar partials read. Shared by
    # the sidebar controller and by actions that re-render the sidebar (star,
    # mark unread). The actual computation lives in Sidebars::Data so the
    # background broadcast path renders identical data.
    def assign_sidebar_memberships
      Sidebars::Data.for(Current.user).each do |name, value|
        instance_variable_set("@#{name}", value)
      end
    end
end
