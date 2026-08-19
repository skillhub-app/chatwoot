json.payload do
  json.partial! 'api/v1/accounts/llm_provider_credentials/partials/credential', formats: [:json], credential: @credential
end
