json.payload do
  json.array! @credentials do |credential|
    json.partial! 'api/v1/accounts/llm_provider_credentials/partials/credential', formats: [:json], credential: credential
  end
end
