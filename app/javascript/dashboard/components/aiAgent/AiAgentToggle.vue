<!-- eslint-disable vue/no-bare-strings-in-template -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const loading = ref(false);
const aiConv = ref(null);
const resettingMemory = ref(false);
const showResetConfirm = ref(false);
const resetDone = ref(false);

const STATE_INFO = {
  active: {
    toggleOn: true,
    locked: false,
    badge: null,
  },
  transferred: {
    toggleOn: false,
    locked: false,
    badge: {
      icon: 'i-lucide-user-round-cog',
      text: 'IA pausada — aguardando humano',
      buttonLabel: 'Reativar IA',
    },
  },
  paused: {
    toggleOn: false,
    locked: false,
    badge: {
      icon: 'i-lucide-pause-circle',
      text: 'IA pausada manualmente',
      buttonLabel: 'Reativar IA',
    },
  },
  ended: {
    toggleOn: false,
    locked: true,
    badge: {
      icon: 'i-lucide-lock',
      text: 'Atendimento encerrado',
      buttonLabel: 'Reabrir atendimento',
    },
  },
};

const stateInfo = computed(() => {
  const state = aiConv.value?.state;
  return STATE_INFO[state] ?? { toggleOn: false, locked: false, badge: null };
});

async function loadState() {
  try {
    const { data } = await ConversationApi.getAiAgentState(
      props.conversationId
    );
    aiConv.value = data;
  } catch {
    aiConv.value = null;
  }
}

async function toggleAi(newValue) {
  if (loading.value) return; // previne duplo clique
  loading.value = true;
  const state = newValue ? 'active' : 'paused';
  try {
    await ConversationApi.updateAiAgentState(props.conversationId, state);
    await loadState();
    useAlert(newValue ? 'IA ativada nesta conversa.' : 'IA desativada nesta conversa.');
  } catch {
    // rollback: re-sincroniza a UI com o estado real do backend
    await loadState();
    useAlert('Não foi possível alterar o estado da IA. Tente novamente.');
  } finally {
    loading.value = false;
  }
}

async function reactivate() {
  if (loading.value) return;
  loading.value = true;
  try {
    await ConversationApi.reactivateAiAgent(props.conversationId);
    await loadState();
    useAlert('IA reativada nesta conversa.');
  } catch {
    await loadState();
    useAlert('Não foi possível reativar a IA. Tente novamente.');
  } finally {
    loading.value = false;
  }
}

async function resetMemory() {
  if (!showResetConfirm.value) {
    showResetConfirm.value = true;
    return;
  }
  resettingMemory.value = true;
  showResetConfirm.value = false;
  try {
    await ConversationApi.resetAiMemory(props.conversationId);
    resetDone.value = true;
    setTimeout(() => {
      resetDone.value = false;
    }, 3000);
  } finally {
    resettingMemory.value = false;
  }
}

onMounted(loadState);
</script>

<template>
  <div class="space-y-2">
    <div
      class="flex items-center justify-between px-4 py-2.5 rounded-xl border"
      :class="
        stateInfo.toggleOn
          ? 'border-violet-200 dark:border-violet-800 bg-violet-50 dark:bg-violet-900/20'
          : 'border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800'
      "
    >
      <div class="flex items-center gap-2">
        <span
          class="size-3.5"
          :class="
            stateInfo.toggleOn
              ? 'i-lucide-bot text-violet-500'
              : 'i-lucide-bot-off text-slate-400'
          "
        />
        <span class="text-xs font-medium text-slate-700 dark:text-slate-200">
          Agente IA
        </span>
        <span v-if="aiConv === null" class="text-[10px] text-slate-400">
          (sem agente)
        </span>
      </div>

      <button
        class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full border-2 transition-colors duration-200 focus:outline-none disabled:opacity-50"
        :class="
          stateInfo.toggleOn
            ? 'border-violet-500 bg-violet-500'
            : 'border-slate-300 dark:border-slate-600 bg-slate-200 dark:bg-slate-600'
        "
        :disabled="loading || stateInfo.locked || aiConv === null"
        @click="toggleAi(!stateInfo.toggleOn)"
      >
        <span
          class="inline-block size-4 rounded-full bg-white shadow transition-transform duration-200"
          :class="stateInfo.toggleOn ? 'translate-x-4' : 'translate-x-0'"
        />
      </button>
    </div>

    <!-- Badge de estado não-ativo -->
    <div
      v-if="stateInfo.badge"
      class="px-3 py-2 rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 flex flex-col gap-1.5"
    >
      <div class="flex items-center gap-1.5">
        <span class="size-3.5 text-amber-500" :class="stateInfo.badge.icon" />
        <span class="text-xs font-medium text-amber-700 dark:text-amber-300">
          {{ stateInfo.badge.text }}
        </span>
      </div>
      <p
        v-if="aiConv?.paused_reason"
        class="text-[11px] text-amber-600 dark:text-amber-400 ml-5"
      >
        {{ aiConv.paused_reason }}
      </p>
      <button
        class="ml-5 text-[11px] font-semibold text-violet-600 dark:text-violet-400 hover:text-violet-800 dark:hover:text-violet-200 transition-colors text-left"
        :disabled="loading"
        @click="reactivate"
      >
        {{ loading ? 'Aguarde...' : stateInfo.badge.buttonLabel }}
      </button>
    </div>

    <!-- Reset memory -->
    <div class="px-1">
      <div
        v-if="resetDone"
        class="text-[11px] text-emerald-500 flex items-center gap-1"
      >
        <span class="i-lucide-check size-3" /> Memória desta conversa apagada.
      </div>
      <div v-else-if="showResetConfirm" class="flex items-center gap-2">
        <span class="text-[11px] text-slate-500"
          >Apagar memória da IA nesta conversa?</span
        >
        <button
          class="text-[11px] font-semibold text-red-500 hover:text-red-700 transition-colors"
          :disabled="resettingMemory"
          @click="resetMemory"
        >
          {{ resettingMemory ? 'Apagando...' : 'Confirmar' }}
        </button>
        <button
          class="text-[11px] text-slate-400 hover:text-slate-600 transition-colors"
          @click="showResetConfirm = false"
        >
          Cancelar
        </button>
      </div>
      <button
        v-else
        class="text-[11px] text-slate-400 hover:text-red-500 flex items-center gap-1 transition-colors"
        @click="resetMemory"
      >
        <span class="i-lucide-rotate-ccw size-3" /> Resetar memória desta
        conversa
      </button>
    </div>
  </div>
</template>
