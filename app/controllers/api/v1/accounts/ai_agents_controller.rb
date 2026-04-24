class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  before_action :set_agent, only: [:show, :update, :destroy, :publish_prompt]

  def index
    @agents = Current.account.ai_agents.includes(:inbox, :ai_agent_schedule).order(:name)
    render :index
  end

  def show
    render :show
  end

  def create
    @agent = Current.account.ai_agents.create!(agent_params)
    render :show, status: :created
  end

  def update
    @agent.update!(agent_params)
    render :show
  end

  def destroy
    @agent.destroy!
    head :ok
  end

  def publish_prompt
    @agent.publish_prompt!(params[:prompt], Current.user)
    render :show
  end

  private

  def set_agent
    @agent = Current.account.ai_agents.find(params[:id])
  end

  def agent_params
    params.require(:ai_agent).permit(
      :name, :company, :language, :timezone,
      :message_buffer_seconds, :active, :inbox_id,
      :llm_provider, :llm_model, :llm_api_key_encrypted,
      :tts_enabled, :tts_voice_id, :tts_api_key_encrypted,
      prompt: {}
    )
  end
end
