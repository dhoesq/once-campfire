class AddPinnedToMessages < ActiveRecord::Migration[8.2]
  def change
    add_column :messages, :pinned_at, :datetime
    add_column :messages, :pinned_by_id, :integer
    add_index :messages, [ :room_id, :pinned_at ]
    add_index :messages, :pinned_by_id
  end
end
