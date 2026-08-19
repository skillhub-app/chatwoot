class ChannelUazapi::Api
  CONNECTED_STATES = %w[open connected].freeze
  CONNECTING_STATES = %w[connecting qr syncing].freeze

  def initialize(channel)
    @channel = channel
  end

  # Configure webhook on existing instance (requires instance token)
  def configure_webhook(webhook_url:)
    post('/webhook', {
           instanceName: @channel.uazapi_instance_name,
           url:          webhook_url,
           enabled:      true,
           events:       %w[MESSAGES_UPSERT CONNECTION_UPDATE]
         })
  end

  # GET /instance/connect/:name — returns QR code base64
  def get_qr_code
    get("/instance/connect/#{@channel.uazapi_instance_name}")
  end

  # GET /instance/connectionState/:name — returns connection state
  def connection_state
    get("/instance/connectionState/#{@channel.uazapi_instance_name}")
  end

  def normalized_status
    state = fetch_state
    if CONNECTED_STATES.include?(state)
      'connected'
    elsif CONNECTING_STATES.include?(state)
      'connecting'
    elsif state == 'close'
      'disconnected'
    else
      state.presence || 'unknown'
    end
  rescue StandardError
    'unknown'
  end

  def send_text(phone_number, text)
    post("/message/sendText/#{@channel.uazapi_instance_name}", {
           number: sanitize_phone(phone_number),
           text:   text
         })
  end

  def send_media(phone_number, url:, caption: nil, type: 'image')
    post("/message/sendMedia/#{@channel.uazapi_instance_name}", {
           number:    sanitize_phone(phone_number),
           mediatype: type,
           media:     url,
           caption:   caption
         }.compact)
  end

  def logout_instance
    delete("/instance/logout/#{@channel.uazapi_instance_name}")
  end

  def restart_instance
    put("/instance/restart/#{@channel.uazapi_instance_name}")
  end

  def delete_instance
    delete("/instance/delete/#{@channel.uazapi_instance_name}")
  end

  private

  def fetch_state
    data = connection_state
    state = data.dig('instance', 'state') || data.dig('instance', 'connectionStatus') ||
            data['state'] || data['connectionStatus'] || data['status']
    state.to_s.downcase
  end

  def sanitize_phone(number)
    number.to_s.gsub(/\D/, '')
  end

  def base_url
    @channel.api_base_url.to_s.chomp('/')
  end

  # UAZAPI uses 'token' header with the per-instance token (not a global admin key)
  def instance_token
    @channel.uazapi_instance_token.to_s
  end

  def conn
    @conn ||= Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.options.timeout = 30
      f.headers['token'] = instance_token
    end
  end

  def get(path, params = {})
    resp = conn.get(path) { |r| r.params = params }
    handle_response!(resp)
    resp.body
  end

  def post(path, body = {})
    resp = conn.post(path, body)
    handle_response!(resp)
    resp.body
  end

  def put(path, body = {})
    resp = conn.put(path, body)
    handle_response!(resp)
    resp.body
  end

  def delete(path)
    resp = conn.delete(path)
    handle_response!(resp)
    resp.body
  end

  def handle_response!(resp)
    return if resp.success?

    body = resp.body
    msg = if body.is_a?(Hash)
            body['message'] || body['error'] || body.inspect
          else
            body.to_s
          end

    case resp.status
    when 401 then raise "UAZAPI: token inválido ou ausente (#{msg})"
    when 404 then raise "UAZAPI: instância '#{@channel.uazapi_instance_name}' não encontrada (#{msg})"
    when 405 then raise "UAZAPI: método não suportado para este endpoint (#{msg})"
    when 422 then raise "UAZAPI: dados inválidos (#{msg})"
    else raise "UAZAPI error #{resp.status}: #{msg}"
    end
  end
end
