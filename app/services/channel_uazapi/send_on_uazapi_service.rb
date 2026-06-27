class ChannelUazapi::SendOnUazapiService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Uazapi
  end

  def perform_reply
    send_message
  end

  def send_message
    phone = message.conversation.contact_inbox.source_id
    if message.attachments.any?
      send_attachments(phone)
    elsif message.content.present?
      response = channel.api.send_text(phone, message.content.to_s)
      store_source_id(response)
    end
  rescue StandardError => e
    Rails.logger.error "ChannelUazapi::SendOnUazapiService error: #{e.message}"
    message.update!(status: :failed, external_error: e.message)
  end

  def send_attachments(phone)
    last_response = nil
    message.attachments.each do |att|
      url = att.download_url
      type = attachment_media_type(att.file_type)
      caption = message.content.presence
      last_response = channel.api.send_media(phone, url: url, caption: caption, type: type)
    end
    store_source_id(last_response)
  end

  # v68 — guarda o id do WhatsApp (key.id) retornado pela Uazapi em source_id,
  # pré-requisito para conseguir revogar/apagar a mensagem depois.
  def store_source_id(response)
    sid = extract_source_id(response)
    message.update!(source_id: sid) if sid.present?
  end

  def extract_source_id(response)
    return unless response.is_a?(Hash)

    response.dig('key', 'id') ||
      response['id'] ||
      response['messageid'] ||
      response.dig('message', 'key', 'id') ||
      response.dig('data', 'key', 'id') ||
      response.dig('data', 'id')
  end

  def attachment_media_type(file_type)
    case file_type.to_s
    when 'image'   then 'image'
    when 'video'   then 'video'
    when 'audio'   then 'audio'
    else 'document'
    end
  end
end
