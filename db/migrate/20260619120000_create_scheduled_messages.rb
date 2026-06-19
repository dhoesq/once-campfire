class CreateScheduledMessages < ActiveRecord::Migration[8.2]
  def change
    create_table :scheduled_messages do |t|
      t.integer :room_id, null: false
      t.integer :creator_id, null: false
      t.text :body
      t.string :client_message_id
      t.datetime :deliver_at, null: false
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :scheduled_messages, :room_id
    add_index :scheduled_messages, :creator_id
    add_index :scheduled_messages, :deliver_at
  end
end
