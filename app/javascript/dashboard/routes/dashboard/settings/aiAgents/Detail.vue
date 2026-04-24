<!-- eslint-disable vue/no-bare-strings-in-template, prettier/prettier -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import aiAgentsAPI from '../../../../api/aiAgents';
import AiAgentPromptEditor from '../../../../components/aiAgent/AiAgentPromptEditor.vue';
import AiAgentConfig from '../../../../components/aiAgent/AiAgentConfig.vue';
import AiAgentFaq from '../../../../components/aiAgent/AiAgentFaq.vue';
import AiAgentSchedule from '../../../../components/aiAgent/AiAgentSchedule.vue';
import AiAgentMetrics from '../../../../components/aiAgent/AiAgentMetrics.vue';

const route = useRoute();
const router = useRouter();

const agent = ref(null);
const loading = ref(true);
const activeTab = ref('prompt');

const TABS = [
  { id: 'prompt',   label: 'Editor de Prompt', icon: 'i-lucide-file-text' },
  { id: 'training', label: 'Treinamento',       icon: 'i-lucide-brain' },
  { id: 'config',   label: 'Configurações',     icon: 'i-lucide-settings-2' },
  { id: 'schedule', label: 'Agendamento',       icon: 'i-lucide-calendar' },
  { id: 'metrics',  label: 'Métricas',          icon: 'i-lucide-bar-chart-2' },
];

const agentId = computed(() => Number(route.params.agentId));

onMounted(async () => {
  try {
    const res = await aiAgentsAPI.get(agentId.value);
    agent.value = res.data?.payload;
  } catch {
    router.push({ name: 'ai_agents_index' });
  } finally {
    loading.value = false;
  }
});

function onAgentUpdated(updated) {
  agent.value = updated;
}
</script>

<template>
  <div class="p-6 max-w-5xl mx-auto">
    <!-- Back + title -->
    <div class="flex items-center gap-3 mb-6">
      <button
        class="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
        @click="router.push({ name: 'ai_agents_index' })"
      >
        <span class="i-lucide-arrow-left size-4" />
      </button>
      <div v-if="agent">
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">
          {{ agent.name }}
        </h1>
        <p class="text-xs text-slate-400">
          {{ agent.company || 'Sem empresa' }} ·
          {{ agent.inbox?.name || 'Sem inbox' }}
        </p>
      </div>
      <div
        v-else
        class="h-6 w-40 bg-slate-200 dark:bg-slate-700 rounded animate-pulse"
      />
    </div>

    <!-- Tabs -->
    <div
      class="flex gap-1 mb-6 border-b border-slate-200 dark:border-slate-700"
    >
      <button
        v-for="tab in TABS"
        :key="tab.id"
        class="flex items-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors border-b-2 -mb-px"
        :class="
          activeTab === tab.id
            ? 'border-violet-500 text-violet-600 dark:text-violet-400'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300'
        "
        @click="activeTab = tab.id"
      >
        <span class="size-3.5" :class="[tab.icon]" />
        {{ tab.label }}
      </button>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex justify-center py-20">
      <span class="i-lucide-loader-2 size-6 animate-spin text-slate-400" />
    </div>

    <template v-else-if="agent">
      <!-- Prompt Editor -->
      <AiAgentPromptEditor
        v-if="activeTab === 'prompt'"
        :agent="agent"
        @updated="onAgentUpdated"
      />

      <!-- Treinamento -->
      <AiAgentFaq v-else-if="activeTab === 'training'" :agent-id="agentId" />

      <!-- Config -->
      <AiAgentConfig
        v-else-if="activeTab === 'config'"
        :agent="agent"
        @updated="onAgentUpdated"
      />

      <!-- Agendamento -->
      <AiAgentSchedule
        v-else-if="activeTab === 'schedule'"
        :agent-id="agentId"
      />

      <!-- Métricas -->
      <AiAgentMetrics v-else-if="activeTab === 'metrics'" :agent-id="agentId" />
    </template>
  </div>
</template>
