import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import AiAgentToggle from './AiAgentToggle.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    getAiAgentState: vi.fn(),
    updateAiAgentState: vi.fn(),
    reactivateAiAgent: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

// bug I: o toggle só carregava o estado da IA uma vez, em onMounted — se o
// backend pausava a IA sozinho (resposta humana) enquanto a conversa já
// estava aberta, a UI ficava travada mostrando "ligado" indefinidamente.
describe('AiAgentToggle (bug I — live refresh)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    ConversationApi.getAiAgentState.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('carrega o state uma vez ao montar', async () => {
    ConversationApi.getAiAgentState.mockResolvedValue({
      data: { state: 'active' },
    });
    mount(AiAgentToggle, { props: { conversationId: 1 } });
    await flushPromises();

    expect(ConversationApi.getAiAgentState).toHaveBeenCalledWith(1);
    expect(ConversationApi.getAiAgentState).toHaveBeenCalledTimes(1);
  });

  it('recarrega o state sozinho depois do intervalo de refresh, sem precisar remontar o componente', async () => {
    ConversationApi.getAiAgentState.mockResolvedValue({
      data: { state: 'active' },
    });
    mount(AiAgentToggle, { props: { conversationId: 1 } });
    await flushPromises();
    expect(ConversationApi.getAiAgentState).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(15000);
    expect(ConversationApi.getAiAgentState).toHaveBeenCalledTimes(2);

    await vi.advanceTimersByTimeAsync(15000);
    expect(ConversationApi.getAiAgentState).toHaveBeenCalledTimes(3);
  });

  it('reflete um pause automático que aconteceu no backend enquanto o painel já estava aberto', async () => {
    ConversationApi.getAiAgentState.mockResolvedValueOnce({
      data: { state: 'active' },
    });
    const wrapper = mount(AiAgentToggle, { props: { conversationId: 1 } });
    await flushPromises();
    expect(wrapper.text()).not.toContain('IA pausada');

    // backend pausou sozinho (pause_ai_on_human_response) — próximo poll deve pegar
    ConversationApi.getAiAgentState.mockResolvedValueOnce({
      data: { state: 'paused', paused_reason: 'manual' },
    });
    await vi.advanceTimersByTimeAsync(15000);
    await flushPromises();

    expect(wrapper.text()).toContain('IA pausada manualmente');
  });

  it('para de dar poll depois que o componente desmonta (não vaza timer)', async () => {
    ConversationApi.getAiAgentState.mockResolvedValue({
      data: { state: 'active' },
    });
    const wrapper = mount(AiAgentToggle, { props: { conversationId: 1 } });
    await flushPromises();

    wrapper.unmount();
    ConversationApi.getAiAgentState.mockClear();

    await vi.advanceTimersByTimeAsync(60000);
    expect(ConversationApi.getAiAgentState).not.toHaveBeenCalled();
  });

  it('ao trocar de conversationId, recarrega imediatamente pro novo id (regressão: componente reaproveitado pelo painel)', async () => {
    ConversationApi.getAiAgentState.mockResolvedValue({
      data: { state: 'active' },
    });
    const wrapper = mount(AiAgentToggle, { props: { conversationId: 1 } });
    await flushPromises();
    ConversationApi.getAiAgentState.mockClear();

    await wrapper.setProps({ conversationId: 2 });
    await flushPromises();

    expect(ConversationApi.getAiAgentState).toHaveBeenCalledWith(2);
  });
});
