class CreateBookmarks < ActiveRecord::Migration[8.2]
  def change
    create_table :bookmarks do |t|
      t.integer :user_id, null: false
      t.integer :message_id, null: false
      t.timestamps
    end

    add_index :bookmarks, :user_id
    add_index :bookmarks, :message_id
    add_index :bookmarks, [ :user_id, :message_id ], unique: true
  end
end
