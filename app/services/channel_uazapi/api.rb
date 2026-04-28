class ChannelUazapi::Api
  CONNECTED_STATES = %w[open connected].freeze
  CONNECTING_STATES = %w[connecting qr syncing].freeze

  def initialize(channel)
    @channel = channel
  end

  def create_instance(webhook_url:)
    post('/instance/create', {
           instanceName: @channel.uazapi_instance_name,
           webhook:      webhook_url,
           qrcode:       true,
           events:       %w[MESSAGES_UPSERT CONNECTION_UPDATE]
         })
  end

  def get_qr_code
    get("/instance/connect/#{@channel.uazapi_instance_name}")
  end

  def connection_state
    get("/instance/connectionState/#{@channel.uazapi_instance_name}")
  end

  def instance_info
    get('/instance/fetchInstances', { instanceName: @channel.uazapi_instance_name })
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
    # { "instance": { "instanceName": "...", "state": "open" } }
    state = data.dig('instance', 'state') || data.dig('instance', 'connectionStatus') ||
            data['state'] || data['connectionStatus'] || data['status']
    state.to_s.downcase
  rescue StandardError
    raw = instance_info
    items = raw.is_a?(Array) ? raw : [raw]
    item = items.find { |i| i['instanceName'] == @channel.uazapi_instance_name } || {}
    (item.dig('instance', 'connectionStatus') || item['connectionStatus'] || item['state'] || '').downcase
  end

  def sanitize_phone(number)
    number.to_s.gsub(/\D/, '')
  end

  def base_url
    @channel.api_base_url.to_s.chomp('/')
  end

  def admin_token
    @channel.admin_token
  end

  def conn
    @conn ||= Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.options.timeout = 30
      f.headers['apikey'] = admin_token
    end
  end

  def get(path, params = {})
    resp = conn.get(path) { |r| r.params = params }
    raise "UAZAPI error #{resp.status}: #{resp.body.inspect}" unless resp.success?

    resp.body
  end

  def post(path, body = {})
    resp = conn.post(path, body)
    raise "UAZAPI error #{resp.status}: #{resp.body.inspect}" unless resp.success?

    resp.body
  end

  def put(path, body = {})
    resp = conn.put(path, body)
    raise "UAZAPI error #{resp.status}: #{resp.body.inspect}" unless resp.success?

    resp.body
  end

  def delete(path)
    resp = conn.delete(path)
    raise "UAZAPI error #{resp.status}: #{resp.body.inspect}" unless resp.success?

    resp.body
  end
end
