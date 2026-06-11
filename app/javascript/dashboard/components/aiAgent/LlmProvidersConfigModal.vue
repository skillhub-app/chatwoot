<!-- eslint-disable vue/no-bare-strings-in-template -->
<script setup>
import { ref, onMounted } from 'vue';
import LlmProviderCredentialsAPI from '../../api/llmProviderCredentials';
import ProviderForm from './ProviderForm.vue';

defineProps({
  show: { type: Boolean, default: false },
});
defineEmits(['close']);

const TABS = [
  { key: 'openai', label: 'OpenAI' },
  { key: 'anthropic', label: 'Anthropic' },
  { key: 'gemini', label: 'Gemini' },
];

const activeTab = ref('openai');
const loading = ref(false);
const credentials = ref({ openai: null, anthropic: null, gemini: null });

async function loadCredentials() {
  loading.value = true;
  try {
    const { data } = await LlmProviderCredentialsAPI.getAll();
    const fresh = { openai: null, anthropic: null, gemini: null };
    (data.payload || []).forEach(c => {
      fresh[c.provider] = c;
    });
    credentials.value = fresh;
  } finally {
    loading.value = false;
  }
}

onMounted(loadCredentials);
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
    @click.self="$emit('close')"
  >
    <div
      class="bg-white dark:bg-slate-900 rounded-xl shadow-xl w-full max-w-lg p-6 flex flex-col gap-4"
    >
      <div class="flex items-start justify-between">
        <div>
          <h2 class="text-base font-semibold text-slate-800 dark:text-slate-100">
            LLM Providers
          </h2>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-1">
            Configure as chaves de API dos provedores. Cada provider aceita uma
            chave por conta — essa chave será usada por todos os agentes que
            selecionarem este provider.
          </p>
        </div>
        <button
          class="text-slate-400 hover:text-slate-600"
          @click="$emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <div class="flex gap-1 border-b border-slate-200 dark:border-slate-700">
        <button
          v-for="tab in TABS"
          :key="tab.key"
          class="px-3 py-2 text-sm font-medium -mb-px border-b-2"
          :class="
            activeTab === tab.key
              ? 'border-violet-500 text-violet-600 dark:text-violet-400'
              : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300'
          "
          @click="activeTab = tab.key"
        >
          {{ tab.label }}
        </button>
      </div>

      <div v-if="loading" class="py-6 text-center text-sm text-slate-400">
        Carregando...
      </div>
      <ProviderForm
        v-else
        :key="activeTab"
        :provider="activeTab"
        :credential="credentials[activeTab]"
        @saved="loadCredentials"
      />
    </div>
  </div>
</template>
