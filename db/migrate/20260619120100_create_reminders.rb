class CreateReminders < ActiveRecord::Migration[8.2]
  def change
    create_table :reminders do |t|
      t.integer :user_id, null: false
      t.integer :message_id, null: false
      t.datetime :remind_at, null: false
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :reminders, :user_id
    add_index :reminders, :message_id
    add_index :reminders, :remind_at
  end
end
