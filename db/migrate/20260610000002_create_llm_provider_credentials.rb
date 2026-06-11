class CreateLlmProviderCredentials < ActiveRecord::Migration[7.0]
  def change
    create_table :llm_provider_credentials do |t|
      t.references :account, null: false, foreign_key: true
      t.string :provider, null: false
      t.text :api_key, null: false
      t.timestamps

      t.index [:account_id, :provider], unique: true
    end

    add_column :ai_agents, :llm_credential_id, :bigint, null: true
    add_foreign_key :ai_agents, :llm_provider_credentials, column: :llm_credential_id, on_delete: :nullify
    add_index :ai_agents, :llm_credential_id
  end
end
