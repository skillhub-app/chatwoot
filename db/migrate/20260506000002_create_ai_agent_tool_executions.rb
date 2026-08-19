class CreateAiAgentToolExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_tool_executions do |t|
      t.references :ai_agent,           null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :ai_agent_execution, null: true,  foreign_key: { on_delete: :nullify },  index: true
      t.references :ai_agent_tool,      null: true,  foreign_key: { on_delete: :nullify },  index: true
      t.string  :tool_name,   null: false
      t.jsonb   :input_params,  null: false, default: {}
      t.jsonb   :output_result, null: false, default: {}
      t.integer :http_status
      t.string  :status,        null: false, default: 'success'
      t.integer :duration_ms,   null: false, default: 0
      t.text    :error_message

      t.timestamps
    end

    add_index :ai_agent_tool_executions, [:ai_agent_id, :created_at]
    add_index :ai_agent_tool_executions, :status
  end
end
