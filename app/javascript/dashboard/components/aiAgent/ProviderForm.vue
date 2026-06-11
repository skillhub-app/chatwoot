<!-- eslint-disable vue/no-bare-strings-in-template -->
<script setup>
import { ref, computed } from 'vue';
import LlmProviderCredentialsAPI from '../../api/llmProviderCredentials';

const props = defineProps({
  provider: { type: String, required: true },
  credential: { type: Object, default: null },
});
const emit = defineEmits(['saved']);

const PROVIDER_LABELS = {
  openai: 'OpenAI',
  anthropic: 'Anthropic',
  gemini: 'Google Gemini',
};

const apiKey = ref('');
const saving = ref(false);
const removing = ref(false);
const error = ref(null);
const showRemoveConfirm = ref(false);

const hasKey = computed(() => props.credential?.has_api_key === true);
const providerLabel = computed(
  () => PROVIDER_LABELS[props.provider] || props.provider
);

async function save() {
  if (!apiKey.value) return;
  saving.value = true;
  error.value = null;
  try {
    await LlmProviderCredentialsAPI.create(props.provider, apiKey.value);
    apiKey.value = '';
    emit('saved');
  } catch {
    error.value = 'Erro ao salvar a chave. Tente novamente.';
  } finally {
    saving.value = false;
  }
}

async function remove() {
  if (!showRemoveConfirm.value) {
    showRemoveConfirm.value = true;
    return;
  }
  removing.value = true;
  error.value = null;
  try {
    await LlmProviderCredentialsAPI.delete(props.credential.id);
    showRemoveConfirm.value = false;
    emit('saved');
  } catch {
    error.value = 'Erro ao remover a chave. Tente novamente.';
  } finally {
    removing.value = false;
  }
}
</script>

<template>
  <form class="flex flex-col gap-3" @submit.prevent="save">
    <div>
      <label
        class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
      >
        API Key
      </label>
      <input
        v-model="apiKey"
        type="password"
        autocomplete="off"
        :placeholder="hasKey ? '••••••••••••' : 'Cole sua API key aqui'"
        class="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 px-3 py-2 text-sm text-slate-800 dark:text-slate-100"
      />
    </div>

    <p
      v-if="hasKey"
      class="text-xs text-emerald-600 dark:text-emerald-400 flex items-center gap-1"
    >
      <span class="i-lucide-check-circle size-3.5" />
      Chave configurada. Cole uma nova chave acima para substituir.
    </p>
    <p
      v-else
      class="text-xs text-amber-600 dark:text-amber-400 flex items-center gap-1"
    >
      <span class="i-lucide-alert-triangle size-3.5" />
      Sem chave configurada. Agentes que selecionarem {{ providerLabel }} não
      funcionarão até esta ser configurada.
    </p>

    <p v-if="error" class="text-xs text-red-500">{{ error }}</p>

    <div class="flex items-center gap-2">
      <button
        type="submit"
        :disabled="!apiKey || saving"
        class="px-3 py-1.5 rounded-lg bg-violet-600 text-white text-sm font-medium disabled:opacity-50"
      >
        {{ saving ? 'Salvando...' : 'Salvar' }}
      </button>
      <button
        v-if="hasKey"
        type="button"
        :disabled="removing"
        class="px-3 py-1.5 rounded-lg border border-red-300 dark:border-red-700 text-red-600 dark:text-red-400 text-sm font-medium disabled:opacity-50"
        @click="remove"
      >
        {{
          showRemoveConfirm
            ? 'Confirmar remoção? Agentes deste provider param de funcionar'
            : 'Remover chave'
        }}
      </button>
      <button
        v-if="showRemoveConfirm"
        type="button"
        class="px-3 py-1.5 rounded-lg text-sm text-slate-500"
        @click="showRemoveConfirm = false"
      >
        Cancelar
      </button>
    </div>
  </form>
</template>
