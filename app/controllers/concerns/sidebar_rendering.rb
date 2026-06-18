module SidebarRendering
  extend ActiveSupport::Concern

  DIRECT_PLACEHOLDERS = 20

  private
    # Computes the membership groups the sidebar renders, assigning the same
    # instance variables used by users/sidebars/show. Shared by the sidebar
    # controller and by actions that re-render the sidebar (star, mark unread).
    def assign_sidebar_memberships
      all_memberships = Current.user.memberships.visible.with_ordered_room

      @starred_memberships = all_memberships.select(&:starred?).sort_by(&:starred_at).reverse
      non_starred          = all_memberships.without(@starred_memberships)
      @direct_memberships  = non_starred.select { |m| m.room.direct? }.sort_by { |m| m.room.updated_at }.reverse
      @other_memberships   = non_starred.without(@direct_memberships)

      @direct_placeholder_users = sidebar_direct_placeholder_users
    end

    def sidebar_direct_placeholder_users
      exclude_user_ids = sidebar_user_ids_already_in_directs.including(Current.user.id)
      User.active.where.not(id: exclude_user_ids).order(:created_at).limit([ DIRECT_PLACEHOLDERS - exclude_user_ids.count, 0 ].max)
    end

    def sidebar_user_ids_already_in_directs
      Membership.where(room_id: Current.user.rooms.directs.pluck(:id)).pluck(:user_id).uniq
    end
end
