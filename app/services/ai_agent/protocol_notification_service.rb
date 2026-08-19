class AiAgent::ProtocolNotificationService
  def self.call(phone:, summary:, account:)
    new(phone: phone, summary: summary, account: account).call
  end

  def initialize(phone:, summary:, account:)
    @phone   = phone
    @summary = summary
    @account = account
  end

  def call
    return if @phone.blank? || @summary.blank?

    instance   = config('UAZAPI_NOTIFICATION_INSTANCE')
    base_url   = config('UAZAPI_BASE_URL')
    admin_token = config('UAZAPI_ADMIN_TOKEN')

    if instance.blank?
      Rails.logger.warn '[ProtocolNotify] UAZAPI_NOTIFICATION_INSTANCE não configurado — notificação ignorada'
      return
    end

    if base_url.blank? || admin_token.blank?
      Rails.logger.error '[ProtocolNotify] UAZAPI_BASE_URL ou UAZAPI_ADMIN_TOKEN ausentes — notificação abortada'
      return
    end

    send_message(base_url, admin_token, instance)
  rescue StandardError => e
    Rails.logger.error "[ProtocolNotify] Falha ao enviar notificação WhatsApp: #{e.message}"
  end

  private

  def config(name)
    InstallationConfig.find_by(name: name)&.value
  end

  def send_message(base_url, admin_token, instance)
    text = "🔔 *Notificação de Protocolo IA*\n\n#{@summary}"
    conn = build_conn(base_url, admin_token)
    resp = conn.post("/message/sendText/#{instance}", {
                       number: sanitize_phone(@phone),
                       text:   text
                     })

    unless resp.success?
      body = resp.body.is_a?(Hash) ? (resp.body['message'] || resp.body.inspect) : resp.body.to_s
      Rails.logger.error "[ProtocolNotify] UAZAPI respondeu #{resp.status}: #{body}"
    end
  end

  def build_conn(base_url, admin_token)
    Faraday.new(url: base_url.to_s.chomp('/')) do |f|
      f.request :json
      f.response :json
      f.options.timeout = 15
      f.headers['token'] = admin_token
    end
  end

  def sanitize_phone(number)
    number.to_s.gsub(/\D/, '')
  end
end
