class Channel::Uazapi < ApplicationRecord
  include Channelable

  self.table_name = 'channel_uazapi'

  EDITABLE_ATTRS = %i[uazapi_instance_name phone_number].freeze

  belongs_to :account

  validates :uazapi_instance_name, presence: true, uniqueness: true
  validate :uazapi_must_be_enabled, on: :create
  validate :instance_limit_not_exceeded, on: :create

  has_secure_token :identifier

  after_create :provision_instance

  def name
    'Uazapi'
  end

  def api_base_url
    InstallationConfig.find_by(name: 'UAZAPI_BASE_URL')&.value.presence ||
      ENV.fetch('UAZAPI_BASE_URL', nil)
  end

  def admin_token
    InstallationConfig.find_by(name: 'UAZAPI_ADMIN_TOKEN')&.value.presence ||
      ENV.fetch('UAZAPI_ADMIN_TOKEN', nil)
  end

  def uazapi_enabled?
    enabled = InstallationConfig.find_by(name: 'UAZAPI_ENABLED')&.value
    enabled.to_s.downcase.in?(%w[true 1 yes])
  end

  def api
    @api ||= ChannelUazapi::Api.new(self)
  end

  private

  def uazapi_must_be_enabled
    errors.add(:base, 'UAZAPI não está habilitada nesta instalação') unless uazapi_enabled?
  end

  def instance_limit_not_exceeded
    return unless account

    limit_str = InstallationConfig.find_by(name: 'UAZAPI_DEFAULT_INSTANCE_LIMIT')&.value
    limit = limit_str.to_i.positive? ? limit_str.to_i : 5
    current = account.uazapi_channels.count
    errors.add(:base, "Limite de instâncias UAZAPI atingido (#{current}/#{limit})") if current >= limit
  end

  def provision_instance
    unless api_base_url.present? && admin_token.present?
      Rails.logger.warn "Channel::Uazapi [#{uazapi_instance_name}] UAZAPI_BASE_URL ou UAZAPI_ADMIN_TOKEN não configurados — instância não provisionada"
      return
    end

    webhook_url = "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/uazapi/#{identifier}"
    Rails.logger.info "Channel::Uazapi [#{uazapi_instance_name}] provisionando em #{api_base_url}"
    result = api.create_instance(webhook_url: webhook_url)
    Rails.logger.info "Channel::Uazapi [#{uazapi_instance_name}] provisionado: #{result.inspect}"
  rescue StandardError => e
    Rails.logger.error "Channel::Uazapi [#{uazapi_instance_name}] provision_instance FALHOU: #{e.message}"
  end
end
