class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update

  def index
    @messages = message_finder.perform
  end

  def create
    begin
      user = Current.user || @resource
      mb = Messages::MessageBuilder.new(user, @conversation, params)
      @message = mb.perform
    rescue StandardError => e
      Rails.logger.error "[MessagesController#create] caught: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.first(20).join("\n")
      render_could_not_create_error(e.message)
    end
  rescue StandardError => e
    Rails.logger.error "[MessagesController#create OUTER] caught: #{e.class.name}: #{e.message}"
    Rails.logger.error e.backtrace.first(20).join("\n")
    raise
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    # v68 — soft delete + revoke no WhatsApp (Uazapi). Só outgoing; conteúdo é
    # preservado (auditoria), mensagem fica visível no painel com a tarja.
    return render_cannot_delete_incoming unless message.outgoing?
    return render_already_deleted if message.soft_deleted?

    if uazapi_channel? && message.source_id.present?
      result = ChannelUazapi::RevokeMessageService.new(message.inbox.channel, message.source_id).perform
      return render_revoke_failed(result) unless result[:success]

      mark_deleted!(for_recipient: true)
    else
      # Não-Uazapi, OU mensagem antiga sem source_id: soft delete apenas local.
      mark_deleted!(for_recipient: false)
    end

    @message = message
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end

  # v68 — soft delete helpers
  def uazapi_channel?
    message.inbox.channel_type == 'Channel::Uazapi'
  end

  def mark_deleted!(for_recipient:)
    now = Time.current
    message.update!(
      deleted_at: now,
      deleted_for_recipient: for_recipient,
      content_attributes: message.content_attributes.merge(
        'deleted' => true, 'deleted_for_recipient' => for_recipient, 'deleted_at' => now.iso8601
      )
    )
  end

  def render_cannot_delete_incoming
    render json: { error: I18n.t('conversations.messages.only_outgoing_deletable') }, status: :forbidden
  end

  def render_already_deleted
    render json: { error: I18n.t('conversations.messages.already_deleted') }, status: :unprocessable_entity
  end

  def render_revoke_failed(result)
    render json: { error: I18n.t('conversations.messages.revoke_failed'), detail: result[:error] }, status: :unprocessable_entity
  end
end
