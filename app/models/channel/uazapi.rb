class Channel::Uazapi < ApplicationRecord
  include Channelable

  self.table_name = 'channel_uazapi'

  EDITABLE_ATTRS = %i[uazapi_instance_name uazapi_instance_token phone_number].freeze

  belongs_to :account

  validates :uazapi_instance_name, presence: true, uniqueness: true
  validates :uazapi_instance_token, presence: true
  validate :uazapi_must_be_enabled, on: :create
  validate :instance_limit_not_exceeded, on: :create

  has_secure_token :identifier

  after_create :configure_webhook

  def name
    'Uazapi'
  end

  def api_base_url
    InstallationConfig.find_by(name: 'UAZAPI_BASE_URL')&.value.presence ||
      ENV.fetch('UAZAPI_BASE_URL', nil)
  end

  def uazapi_enabled?
    enabled = InstallationConfig.find_by(name: 'UAZAPI_ENABLED')&.value
    enabled.to_s.downcase.in?(%w[true 1 yes])
  end

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/uazapi/#{identifier}"
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

  def configure_webhook
    return unless api_base_url.present? && uazapi_instance_token.present?

    api.configure_webhook(webhook_url: webhook_url)
    Rails.logger.info "Channel::Uazapi [#{uazapi_instance_name}] webhook configurado: #{webhook_url}"
  rescue StandardError => e
    Rails.logger.warn "Channel::Uazapi [#{uazapi_instance_name}] configure_webhook falhou (configure manualmente): #{e.message}"
  end
end
