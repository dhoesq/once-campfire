class Users::SidebarsController < ApplicationController
  include SidebarRendering

  def show
    assign_sidebar_memberships
  end
end
