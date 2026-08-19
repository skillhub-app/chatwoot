class AddSoftDeleteToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :deleted_at, :datetime
    add_column :messages, :deleted_for_recipient, :boolean, default: false, null: false
    add_index :messages, :deleted_at
  end
end
