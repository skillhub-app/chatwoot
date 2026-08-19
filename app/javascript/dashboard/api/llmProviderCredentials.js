/* global axios */
import ApiClient from './ApiClient';

class LlmProviderCredentialsAPI extends ApiClient {
  constructor() {
    super('llm_provider_credentials', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  create(provider, apiKey) {
    return axios.post(this.url, { provider, api_key: apiKey });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new LlmProviderCredentialsAPI();
