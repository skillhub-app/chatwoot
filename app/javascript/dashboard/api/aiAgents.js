/* global axios */
import ApiClient from './ApiClient';

class AiAgentsAPI extends ApiClient {
  constructor() {
    super('ai_agents', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  get(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { ai_agent: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { ai_agent: data });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  publishPrompt(id, prompt) {
    return axios.post(`${this.url}/${id}/publish_prompt`, { prompt });
  }
}

export default new AiAgentsAPI();
