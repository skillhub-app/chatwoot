class Api::V1::Accounts::LlmProviderCredentialsController < Api::V1::Accounts::BaseController
  before_action :fetch_credential, only: [:update, :destroy]

  def index
    @credentials = Current.account.llm_provider_credentials.order(:provider)
  end

  # Upsert: se já existe credential pro provider, atualiza a key
  def create
    @credential = Current.account.llm_provider_credentials.find_or_initialize_by(
      provider: permitted_params[:provider]
    )
    @credential.api_key = permitted_params[:api_key]
    @credential.save!
    render :show, status: :created
  end

  def update
    @credential.update!(api_key: permitted_params[:api_key])
    render :show
  end

  def destroy
    @credential.destroy!
    head :no_content
  end

  private

  def fetch_credential
    @credential = Current.account.llm_provider_credentials.find(params[:id])
  end

  def permitted_params
    params.permit(:provider, :api_key)
  end
end
