class AddArchivedAtToRooms < ActiveRecord::Migration[8.2]
  def change
    add_column :rooms, :archived_at, :datetime
    add_index :rooms, :archived_at
  end
end
