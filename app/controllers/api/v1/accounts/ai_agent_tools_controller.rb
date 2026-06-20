class Api::V1::Accounts::AiAgentToolsController < Api::V1::Accounts::BaseController
  before_action :set_agent
  before_action :set_tool, only: [:show, :update, :destroy, :test]

  def index
    @tools = @agent.tools.ordered
    render json: { payload: @tools.map { |t| tool_json(t) } }
  end

  def show
    render json: { payload: tool_json(@tool) }
  end

  def create
    @tool = @agent.tools.create!(tool_params)
    render json: { payload: tool_json(@tool) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @tool.update!(tool_params)
    render json: { payload: tool_json(@tool) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    @tool.destroy!
    head :ok
  end

  # POST /tools/:id/test — admin preview, does NOT create AiAgentToolExecution
  def test
    params_input = params[:params].present? ? params[:params].to_unsafe_h : {}
    context = {
      account_id:      Current.account.id,
      conversation_id: params[:conversation_id],
      contact_id:      params[:contact_id]
    }

    executor = AiAgent::ToolExecutor.new(@tool, params_input, context)

    # Run but skip the log (test mode)
    result = executor.send(:execute_request)
    duration = result[:duration_ms] || 0

    render json: {
      payload: {
        success:          result[:success?],
        http_status:      result[:http_status],
        output:           result[:output],
        formatted_for_llm: result[:formatted_for_llm],
        duration_ms:      duration,
        error_message:    result[:error_message]
      }
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_agent
    @agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_tool
    @tool = @agent.tools.find(params[:id])
  end

  def tool_params
    params.require(:tool).permit(
      :name, :description, :http_method, :endpoint_url,
      :request_body_template, :response_template, :when_to_use,
      :timeout_seconds, :active, :position,
      parameters_schema: {},
      headers: {}
    )
  end

  def tool_json(t)
    {
      id:                    t.id,
      name:                  t.name,
      description:           t.description,
      parameters_schema:     t.parameters_schema,
      http_method:           t.http_method,
      endpoint_url:          t.endpoint_url,
      headers:               t.headers,
      request_body_template: t.request_body_template,
      response_template:     t.response_template,
      when_to_use:           t.when_to_use,
      timeout_seconds:       t.timeout_seconds,
      active:                t.active,
      position:              t.position,
      is_native:             t.is_native,
      native_key:            t.native_key,
      created_at:            t.created_at.to_i,
      updated_at:            t.updated_at.to_i
    }
  end
end
