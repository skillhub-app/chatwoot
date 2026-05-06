class CreateAiAgentTools < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_tools do |t|
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string  :name,                    null: false
      t.text    :description,             null: false
      t.jsonb   :parameters_schema,       null: false, default: {}
      t.string  :http_method,             null: false, default: 'POST'
      t.string  :endpoint_url,            null: false
      t.jsonb   :headers,                 null: false, default: {}
      t.text    :request_body_template
      t.text    :response_template
      t.text    :when_to_use
      t.integer :timeout_seconds,         null: false, default: 10
      t.boolean :active,                  null: false, default: true
      t.integer :position,                null: false, default: 0

      t.timestamps
    end

    add_index :ai_agent_tools, [:ai_agent_id, :name], unique: true
    add_index :ai_agent_tools, [:ai_agent_id, :active]
    add_index :ai_agent_tools, [:ai_agent_id, :position]
  end
end
