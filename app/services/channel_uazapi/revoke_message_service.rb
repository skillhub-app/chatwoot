# frozen_string_literal: true

# Sprint v68 — revoga (apaga no WhatsApp do lead) uma mensagem via Uazapi.
#
# Reusa a mesma stack HTTP do ChannelUazapi::Api (Faraday, base_url da instalação,
# header `token` por instância), mas com tratamento de status PRÓPRIO: ao contrário
# do Api#post (que levanta exceção em não-2xx), aqui 404 é considerado SUCESSO
# (mensagem já não existe na Uazapi = estado desejado, idempotente).
#
# POST {base_url}/message/delete  body: { id: <source_id> }  header: token
class ChannelUazapi::RevokeMessageService
  REQUEST_TIMEOUT = 5

  def initialize(channel, source_id)
    @channel   = channel
    @source_id = source_id
  end

  def perform
    return { success: false, error: 'missing_source_id' } if @source_id.blank?

    resp = conn.post('/message/delete', { id: @source_id })

    case resp.status
    when 200, 404 # 404 = já apagada na Uazapi → idempotente, considera sucesso
      { success: true, code: resp.status, response: resp.body }
    when 400, 401, 500
      { success: false, code: resp.status, error: error_message(resp) }
    else
      { success: false, code: resp.status, error: "unexpected code #{resp.status}" }
    end
  rescue Faraday::TimeoutError, Timeout::Error
    { success: false, error: 'timeout' }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def base_url
    @channel.api_base_url.to_s.chomp('/')
  end

  def conn
    @conn ||= Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.options.timeout = REQUEST_TIMEOUT
      f.headers['token'] = @channel.uazapi_instance_token.to_s
    end
  end

  def error_message(resp)
    body = resp.body
    return body.to_s unless body.is_a?(Hash)

    body['message'] || body['error'] || body.to_s
  end
end
