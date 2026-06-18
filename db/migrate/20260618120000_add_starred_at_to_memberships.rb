class AddStarredAtToMemberships < ActiveRecord::Migration[8.2]
  def change
    add_column :memberships, :starred_at, :datetime
    add_index :memberships, [ :user_id, :starred_at ]
  end
end
