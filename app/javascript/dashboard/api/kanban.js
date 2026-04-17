/* global axios */
import ApiClient from './ApiClient';

class KanbanPipelinesAPI extends ApiClient {
  constructor() {
    super('kanban/pipelines', { accountScoped: true });
  }
}

class KanbanStagesAPI extends ApiClient {
  constructor() {
    super('kanban/pipelines', { accountScoped: true });
  }

  stagesUrl(pipelineId) {
    return `${this.url}/${pipelineId}/stages`;
  }

  list(pipelineId) {
    return axios.get(this.stagesUrl(pipelineId));
  }

  create(pipelineId, data) {
    return axios.post(this.stagesUrl(pipelineId), data);
  }

  update(pipelineId, id, data) {
    return axios.patch(`${this.stagesUrl(pipelineId)}/${id}`, data);
  }

  reorder(pipelineId, id, position) {
    return axios.patch(`${this.stagesUrl(pipelineId)}/${id}/reorder`, {
      position,
    });
  }

  delete(pipelineId, id) {
    return axios.delete(`${this.stagesUrl(pipelineId)}/${id}`);
  }
}

class KanbanItemsAPI extends ApiClient {
  constructor() {
    super('kanban/pipelines', { accountScoped: true });
  }

  itemsUrl(pipelineId) {
    return `${this.url}/${pipelineId}/items`;
  }

  list(pipelineId, params = {}) {
    return axios.get(this.itemsUrl(pipelineId), { params });
  }

  show(pipelineId, id) {
    return axios.get(`${this.itemsUrl(pipelineId)}/${id}`);
  }

  create(pipelineId, data) {
    return axios.post(this.itemsUrl(pipelineId), data);
  }

  update(pipelineId, id, data) {
    return axios.patch(`${this.itemsUrl(pipelineId)}/${id}`, data);
  }

  move(pipelineId, id, stageId, position) {
    return axios.patch(`${this.itemsUrl(pipelineId)}/${id}/move`, {
      stage_id: stageId,
      position,
    });
  }

  won(pipelineId, id) {
    return axios.patch(`${this.itemsUrl(pipelineId)}/${id}/won`);
  }

  lost(pipelineId, id) {
    return axios.patch(`${this.itemsUrl(pipelineId)}/${id}/lost`);
  }

  reopen(pipelineId, id) {
    return axios.patch(`${this.itemsUrl(pipelineId)}/${id}/reopen`);
  }

  delete(pipelineId, id) {
    return axios.delete(`${this.itemsUrl(pipelineId)}/${id}`);
  }
}

class KanbanItemSubresourceAPI extends ApiClient {
  constructor(subresource) {
    super('kanban/pipelines', { accountScoped: true });
    this.subresource = subresource;
  }

  baseUrl(pipelineId, itemId) {
    return `${this.url}/${pipelineId}/items/${itemId}/${this.subresource}`;
  }

  list(pipelineId, itemId) {
    return axios.get(this.baseUrl(pipelineId, itemId));
  }

  create(pipelineId, itemId, data) {
    return axios.post(this.baseUrl(pipelineId, itemId), data);
  }

  update(pipelineId, itemId, id, data) {
    return axios.patch(`${this.baseUrl(pipelineId, itemId)}/${id}`, data);
  }

  delete(pipelineId, itemId, id) {
    return axios.delete(`${this.baseUrl(pipelineId, itemId)}/${id}`);
  }

  complete(pipelineId, itemId, id) {
    return axios.patch(`${this.baseUrl(pipelineId, itemId)}/${id}/complete`);
  }
}

class KanbanGlobalItemsAPI extends ApiClient {
  constructor() {
    super('kanban/items', { accountScoped: true });
  }

  byConversation(conversationId) {
    return axios.get(this.url, { params: { conversation_id: conversationId } });
  }
}

class KanbanGamificationAPI extends ApiClient {
  constructor() {
    super('kanban/gamification', { accountScoped: true });
  }

  rankings() {
    return axios.get(`${this.url}/rankings`);
  }

  overview() {
    return axios.get(`${this.url}/overview`);
  }

  recentWins() {
    return axios.get(`${this.url}/recent_wins`);
  }
}

class KanbanGoalsAPI extends ApiClient {
  constructor() {
    super('kanban/goals', { accountScoped: true });
  }

  list(year, month) {
    return axios.get(this.url, { params: { year, month } });
  }

  upsert(data) {
    return axios.post(`${this.url}/upsert`, data);
  }
}

export const pipelinesAPI = new KanbanPipelinesAPI();
export const globalItemsAPI = new KanbanGlobalItemsAPI();
export const gamificationAPI = new KanbanGamificationAPI();
export const goalsAPI = new KanbanGoalsAPI();
export const stagesAPI = new KanbanStagesAPI();
export const itemsAPI = new KanbanItemsAPI();
export const tasksAPI = new KanbanItemSubresourceAPI('tasks');
export const notesAPI = new KanbanItemSubresourceAPI('notes');
export const activitiesAPI = new KanbanItemSubresourceAPI('activities');
export const attachmentsAPI = new KanbanItemSubresourceAPI('attachments');
