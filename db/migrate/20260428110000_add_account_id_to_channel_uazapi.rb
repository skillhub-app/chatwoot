class AddAccountIdToChannelUazapi < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_uazapi, :account_id, :bigint
    add_index :channel_uazapi, :account_id

    # Populate account_id from existing inbox associations
    execute <<-SQL
      UPDATE channel_uazapi cu
      SET account_id = i.account_id
      FROM inboxes i
      WHERE i.channel_type = 'Channel::Uazapi'
        AND i.channel_id = cu.id
    SQL
  end
end
