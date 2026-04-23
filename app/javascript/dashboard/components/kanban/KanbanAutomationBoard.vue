<!-- eslint-disable vue/no-bare-strings-in-template, vue/max-attributes-per-line, prettier/prettier -->
<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import KanbanAutomationCard from './KanbanAutomationCard.vue';
import { automationsAPI, stagesAPI } from 'dashboard/api/kanban.js';

const store = useStore();
const router = useRouter();

const pipelines = computed(() => store.getters['kanban/getPipelines'] || []);
const agents = computed(() => store.getters['agents/getAgents'] || []);
const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);

// Active pipeline mirrors the Kanban board selection
const activePipelineId = computed(
  () => store.getters['kanban/getActivePipelineId']
);
const selectedPipelineId = ref(null);

const stages = ref([]);
const automations = ref([]);
const loading = ref(false);

// ── Pipeline dropdown (same pattern as KanbanBoard) ───────────────────────────
const showPipelineDropdown = ref(false);

function selectPipeline(id) {
  selectedPipelineId.value = id;
  store.commit('kanban/SET_ACTIVE_PIPELINE', id);
  showPipelineDropdown.value = false;
}

const selectedPipeline = computed(
  () => pipelines.value.find(p => p.id === selectedPipelineId.value) || null
);

// ── Data loading ──────────────────────────────────────────────────────────────
async function reload() {
  if (!selectedPipelineId.value) return;
  loading.value = true;
  try {
    const [stagesRes, autoRes] = await Promise.all([
      stagesAPI.list(selectedPipelineId.value),
      automationsAPI.list({ pipeline_id: selectedPipelineId.value }),
    ]);
    stages.value = (stagesRes.data.payload || []).sort(
      (a, b) => a.position - b.position
    );
    automations.value = autoRes.data.payload || [];
  } finally {
    loading.value = false;
  }
}

watch(selectedPipelineId, reload);

onMounted(() => {
  selectedPipelineId.value =
    activePipelineId.value || pipelines.value[0]?.id || null;
  if (selectedPipelineId.value) reload();
});

// ── Stage ↔ Automation helpers ────────────────────────────────────────────────
function automationForStage(stageId) {
  return automations.value.find(a => a.trigger_stage_id === stageId) || null;
}

function actionsForStage(stageId) {
  const auto = automationForStage(stageId);
  if (!auto) return [];
  return [...(auto.actions || [])].sort((a, b) => {
    // Sort by delay converted to minutes for true sequential order
    const toMin = (m, t) => {
      if (t === 'hours') return m * 60;
      if (t === 'days') return m * 1440;
      if (t === 'business_days') return m * 1440;
      return m;
    };
    return (
      toMin(a.delay_minutes, a.delay_type) -
      toMin(b.delay_minutes, b.delay_type)
    );
  });
}

async function ensureAutomation(stage) {
  let auto = automationForStage(stage.id);
  if (!auto) {
    const res = await automationsAPI.create({
      pipeline_id: selectedPipelineId.value,
      trigger_stage_id: stage.id,
      name: stage.name,
      active: true,
      stop_on_reply: true,
      stop_on_stage_change: true,
      stop_on_human_takeover: false,
    });
    auto = res.data;
    automations.value.push(auto);
  }
  return auto;
}

// ── Stop conditions per stage ─────────────────────────────────────────────────
const stopConditionsStageId = ref(null);
const stopConditionsTemp = ref({});
const stopConditionsSaving = ref(false);

function openStopConditions(stageId) {
  const auto = automationForStage(stageId);
  stopConditionsTemp.value = auto
    ? {
        stop_on_reply: auto.stop_on_reply,
        stop_on_stage_change: auto.stop_on_stage_change,
        stop_on_human_takeover: auto.stop_on_human_takeover,
      }
    : {
        stop_on_reply: true,
        stop_on_stage_change: true,
        stop_on_human_takeover: false,
      };
  stopConditionsStageId.value = stageId;
}

async function saveStopConditions() {
  stopConditionsSaving.value = true;
  try {
    const stageId = stopConditionsStageId.value;
    let auto = automationForStage(stageId);
    const stage = stages.value.find(s => s.id === stageId);
    if (!auto) {
      auto = await ensureAutomation(stage);
    }
    await automationsAPI.update(auto.id, stopConditionsTemp.value);
    await reload();
  } finally {
    stopConditionsSaving.value = false;
    stopConditionsStageId.value = null;
  }
}

// ── Action form ───────────────────────────────────────────────────────────────
const showActionForm = ref(false);
const actionFormStage = ref(null);
const actionFormEditing = ref(null);
const actionFormSaving = ref(false);
const actionFormError = ref(null);

const ACTION_TYPES = [
  {
    value: 'send_whatsapp',
    label: 'WhatsApp',
    icon: 'i-lucide-message-circle',
    color: 'text-emerald-500',
  },
  {
    value: 'send_webhook',
    label: 'Webhook',
    icon: 'i-lucide-webhook',
    color: 'text-blue-500',
  },
  {
    value: 'create_task',
    label: 'Criar Tarefa',
    icon: 'i-lucide-check-square',
    color: 'text-violet-500',
  },
];

const blankForm = () => ({
  id: null,
  action_type: 'send_whatsapp',
  delay_minutes: 0,
  delay_type: 'minutes',
  active: true,
  config: {},
});

const actionForm = ref(blankForm());

function openAdd(stage) {
  actionFormStage.value = stage;
  actionFormEditing.value = null;
  actionForm.value = {
    ...blankForm(),
    position: actionsForStage(stage.id).length,
  };
  actionFormError.value = null;
  showActionForm.value = true;
}

function openEdit(stage, action) {
  actionFormStage.value = stage;
  actionFormEditing.value = action;
  actionForm.value = {
    id: action.id,
    action_type: action.action_type,
    delay_minutes: action.delay_minutes,
    delay_type: action.delay_type,
    active: action.active,
    config: { ...action.config },
  };
  actionFormError.value = null;
  showActionForm.value = true;
}

function closeActionForm() {
  showActionForm.value = false;
  actionFormStage.value = null;
  actionFormEditing.value = null;
}

function onTypeChange() {
  actionForm.value.config = {};
}

async function saveAction() {
  actionFormSaving.value = true;
  actionFormError.value = null;
  try {
    const auto = await ensureAutomation(actionFormStage.value);
    const data = {
      action_type: actionForm.value.action_type,
      delay_minutes: actionForm.value.delay_minutes,
      delay_type: actionForm.value.delay_type,
      active: actionForm.value.active,
      config: actionForm.value.config,
      position: actionForm.value.position || 0,
    };
    if (actionForm.value.id) {
      await automationsAPI.updateAction(auto.id, actionForm.value.id, data);
    } else {
      await automationsAPI.createAction(auto.id, data);
    }
    await reload();
    closeActionForm();
  } catch {
    actionFormError.value = 'Erro ao salvar. Tente novamente.';
  } finally {
    actionFormSaving.value = false;
  }
}

async function deleteAction(stage, action) {
  if (!window.confirm('Excluir esta atividade?')) return;
  try {
    const auto = automationForStage(stage.id);
    if (!auto) return;
    await automationsAPI.deleteAction(auto.id, action.id);
    await reload();
  } catch {
    /* ignore */
  }
}

async function toggleActive(stage, action) {
  try {
    const auto = automationForStage(stage.id);
    if (!auto) return;
    await automationsAPI.updateAction(auto.id, action.id, {
      active: !action.active,
    });
    await reload();
  } catch {
    /* ignore */
  }
}
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden bg-white dark:bg-slate-900">
    <!-- ── Top bar (mirrors KanbanBoard) ──────────────────────────────────── -->
    <div
      class="flex items-center gap-3 px-5 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0 flex-wrap"
    >
      <!-- Title -->
      <div class="flex items-center gap-2">
        <span class="i-lucide-zap size-5 text-violet-500" />
        <h1 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          Automação de CRM
        </h1>
      </div>

      <!-- Pipeline dropdown (same design as KanbanBoard) -->
      <div class="relative" @click.stop>
        <button
          class="flex items-center gap-2 text-sm px-3 py-1.5 rounded-lg border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 hover:border-violet-400 transition-colors font-medium"
          @click="showPipelineDropdown = !showPipelineDropdown"
        >
          <span class="i-lucide-layers size-3.5 text-violet-500" />
          {{ selectedPipeline?.name || 'Selecionar Pipeline' }}
          <span class="i-lucide-chevron-down size-3.5 text-slate-400" />
        </button>

        <div
          v-if="showPipelineDropdown"
          class="absolute top-full left-0 mt-1 z-40 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-xl w-56 overflow-hidden"
        >
          <div class="py-1">
            <button
              v-for="p in pipelines"
              :key="p.id"
              class="w-full flex items-center justify-between px-3 py-2 text-sm hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
              :class="
                p.id === selectedPipelineId
                  ? 'text-violet-600 font-medium'
                  : 'text-slate-700 dark:text-slate-200'
              "
              @click="selectPipeline(p.id)"
            >
              <span>{{ p.name }}</span>
              <span
                v-if="p.id === selectedPipelineId"
                class="i-lucide-check size-3.5 text-violet-500"
              />
            </button>
          </div>
        </div>
      </div>

      <!-- Spinner -->
      <span
        v-if="loading"
        class="i-lucide-loader-circle size-4 animate-spin text-violet-500"
      />

      <!-- Back to Kanban -->
      <div class="ml-auto">
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700 font-medium transition-colors"
          @click="router.push({ name: 'kanban_board' })"
        >
          <span class="i-lucide-arrow-left size-3.5" />
          Voltar ao Kanban
        </button>
      </div>
    </div>

    <!-- ── Legend bar ─────────────────────────────────────────────────────── -->
    <div
      class="flex items-center gap-4 px-5 py-2 border-b border-slate-100 dark:border-slate-800 bg-slate-50 dark:bg-slate-900/50 shrink-0"
    >
      <span class="text-[11px] text-slate-400 font-medium"
        >Tipos de atividade:</span
      >
      <span
        class="flex items-center gap-1 text-[11px] text-emerald-600 dark:text-emerald-400"
      >
        <span class="i-lucide-message-circle size-3.5" /> WhatsApp
      </span>
      <span
        class="flex items-center gap-1 text-[11px] text-blue-600 dark:text-blue-400"
      >
        <span class="i-lucide-webhook size-3.5" /> Webhook
      </span>
      <span
        class="flex items-center gap-1 text-[11px] text-violet-600 dark:text-violet-400"
      >
        <span class="i-lucide-check-square size-3.5" /> Tarefa
      </span>
      <span class="ml-4 text-[11px] text-slate-400"
        >Cards ordenados por tempo de execução ↓</span
      >
    </div>

    <!-- ── Empty / loading ────────────────────────────────────────────────── -->
    <div
      v-if="!selectedPipelineId || (stages.length === 0 && !loading)"
      class="flex-1 flex flex-col items-center justify-center text-center px-4"
    >
      <span
        class="i-lucide-layout-columns size-12 text-slate-200 dark:text-slate-700 mb-3"
      />
      <p class="text-sm font-medium text-slate-500 dark:text-slate-400">
        {{
          !selectedPipelineId
            ? 'Selecione um pipeline'
            : 'Nenhuma etapa configurada neste pipeline'
        }}
      </p>
    </div>

    <!-- ── Board: columns = stages ────────────────────────────────────────── -->
    <div
      v-else-if="stages.length"
      class="flex-1 overflow-x-auto overflow-y-hidden p-4"
      @click="
        showPipelineDropdown = false;
        stopConditionsStageId = null;
      "
    >
      <div class="flex gap-3 h-full">
        <div
          v-for="stage in stages"
          :key="stage.id"
          class="flex flex-col w-64 shrink-0 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-900 h-full"
          :style="{
            borderTopColor: stage.color || '#8b5cf6',
            borderTopWidth: '3px',
            borderTopStyle: 'solid',
          }"
        >
          <!-- Column header -->
          <div
            class="flex items-center justify-between px-3 py-2.5 border-b border-slate-200 dark:border-slate-700 shrink-0"
          >
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="size-2 rounded-full shrink-0"
                :style="{ backgroundColor: stage.color || '#8b5cf6' }"
              />
              <h3
                class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate"
              >
                {{ stage.name }}
              </h3>
              <span
                class="shrink-0 text-xs font-medium bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300 rounded-full px-1.5 py-0.5 leading-none"
              >
                {{ actionsForStage(stage.id).length }}
              </span>
            </div>

            <div class="flex items-center gap-1 shrink-0">
              <!-- Stop conditions gear -->
              <div class="relative">
                <button
                  class="p-1 rounded text-slate-300 hover:text-violet-500 dark:text-slate-600 dark:hover:text-violet-400 transition-colors"
                  :class="automationForStage(stage.id) ? 'text-violet-400' : ''"
                  title="Condições de parada"
                  @click.stop="openStopConditions(stage.id)"
                >
                  <span class="i-lucide-settings-2 size-3.5" />
                </button>

                <!-- Stop conditions popover -->
                <div
                  v-if="stopConditionsStageId === stage.id"
                  class="absolute top-full right-0 mt-1 z-30 w-52 bg-white dark:bg-slate-800 rounded-xl shadow-xl border border-slate-100 dark:border-slate-700 p-3"
                  @click.stop
                >
                  <p
                    class="text-xs font-semibold text-slate-600 dark:text-slate-300 mb-2"
                  >
                    Parar régua quando:
                  </p>
                  <div class="space-y-2">
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input
                        v-model="stopConditionsTemp.stop_on_reply"
                        type="checkbox"
                        class="rounded border-slate-300 text-violet-600"
                      />
                      <span class="text-xs text-slate-600 dark:text-slate-300"
                        >Lead responder</span
                      >
                    </label>
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input
                        v-model="stopConditionsTemp.stop_on_stage_change"
                        type="checkbox"
                        class="rounded border-slate-300 text-violet-600"
                      />
                      <span class="text-xs text-slate-600 dark:text-slate-300"
                        >Mudar de etapa</span
                      >
                    </label>
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input
                        v-model="stopConditionsTemp.stop_on_human_takeover"
                        type="checkbox"
                        class="rounded border-slate-300 text-violet-600"
                      />
                      <span class="text-xs text-slate-600 dark:text-slate-300"
                        >Agente assumir</span
                      >
                    </label>
                  </div>
                  <div class="flex gap-2 mt-3">
                    <button
                      :disabled="stopConditionsSaving"
                      class="flex-1 text-xs py-1.5 rounded-lg bg-violet-600 text-white hover:bg-violet-700 disabled:opacity-50 font-medium"
                      @click="saveStopConditions"
                    >
                      {{ stopConditionsSaving ? '...' : 'Salvar' }}
                    </button>
                    <button
                      class="text-xs px-2 py-1.5 rounded-lg border border-slate-200 dark:border-slate-700 text-slate-500"
                      @click="stopConditionsStageId = null"
                    >
                      Cancelar
                    </button>
                  </div>
                </div>
              </div>

              <!-- Add action -->
              <button
                class="p-1 rounded text-slate-400 hover:text-violet-500 dark:hover:text-violet-400 transition-colors"
                title="Adicionar atividade"
                @click.stop="openAdd(stage)"
              >
                <span class="i-lucide-plus size-4" />
              </button>
            </div>
          </div>

          <!-- Cards list -->
          <div class="flex-1 overflow-y-auto p-2 space-y-2">
            <!-- Empty state -->
            <div
              v-if="actionsForStage(stage.id).length === 0"
              class="flex flex-col items-center justify-center py-10 text-center"
            >
              <span
                class="i-lucide-zap-off size-7 text-slate-200 dark:text-slate-700 mb-2"
              />
              <p class="text-xs text-slate-300 dark:text-slate-600 mb-2">
                Sem automações
              </p>
              <button
                class="text-xs text-violet-500 hover:underline"
                @click="openAdd(stage)"
              >
                + Adicionar atividade
              </button>
            </div>

            <!-- Activity cards (sorted by delay = sequential order) -->
            <KanbanAutomationCard
              v-for="(action, idx) in actionsForStage(stage.id)"
              :key="action.id"
              :action="action"
              :position="idx"
              @edit="openEdit(stage, action)"
              @delete="deleteAction(stage, action)"
              @toggle-active="toggleActive(stage, action)"
            />
          </div>

          <!-- Column footer: add button -->
          <div
            class="px-2 py-2 border-t border-slate-100 dark:border-slate-800 shrink-0"
          >
            <button
              class="w-full flex items-center justify-center gap-1.5 text-xs py-2 rounded-lg border border-dashed border-slate-200 dark:border-slate-700 text-slate-400 hover:border-violet-300 hover:text-violet-500 hover:bg-violet-50 dark:hover:bg-violet-900/10 transition-colors"
              @click="openAdd(stage)"
            >
              <span class="i-lucide-plus size-3.5" />
              Adicionar atividade
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- ── Action form modal ──────────────────────────────────────────────────── -->
  <Teleport to="body">
    <div
      v-if="showActionForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm"
      @click.self="closeActionForm"
    >
      <div
        class="bg-white dark:bg-slate-900 rounded-2xl shadow-2xl w-full max-w-md mx-4 overflow-hidden"
      >
        <!-- Header -->
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-slate-100 dark:border-slate-800"
        >
          <div>
            <h3
              class="text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              {{ actionFormEditing ? 'Editar atividade' : 'Nova atividade' }}
            </h3>
            <p class="text-xs text-slate-400 mt-0.5">
              {{ actionFormStage?.name }}
            </p>
          </div>
          <button
            class="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 dark:hover:bg-slate-800"
            @click="closeActionForm"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>

        <!-- Body -->
        <div class="px-5 py-4 space-y-4 max-h-[65vh] overflow-y-auto">
          <div
            v-if="actionFormError"
            class="text-xs text-red-600 bg-red-50 dark:bg-red-900/20 rounded-lg px-3 py-2"
          >
            {{ actionFormError }}
          </div>

          <!-- Type selector -->
          <div>
            <label class="text-xs font-medium text-slate-500 mb-1.5 block"
              >Tipo de atividade</label
            >
            <div class="grid grid-cols-3 gap-2">
              <button
                v-for="type in ACTION_TYPES"
                :key="type.value"
                class="flex flex-col items-center gap-1.5 py-3 rounded-xl border-2 transition-all text-center"
                :class="
                  actionForm.action_type === type.value
                    ? 'border-violet-500 bg-violet-50 dark:bg-violet-900/20'
                    : 'border-slate-100 dark:border-slate-700 hover:border-slate-200'
                "
                @click="
                  actionForm.action_type = type.value;
                  onTypeChange();
                "
              >
                <span class="size-5" :class="[type.icon, type.color]" />
                <span
                  class="text-xs font-medium text-slate-600 dark:text-slate-300 leading-tight"
                  >{{ type.label }}</span
                >
              </button>
            </div>
          </div>

          <!-- Delay -->
          <div>
            <label class="text-xs font-medium text-slate-500 mb-1.5 block"
              >Executar após</label
            >
            <div class="flex gap-2">
              <input
                v-model.number="actionForm.delay_minutes"
                type="number"
                min="0"
                placeholder="0"
                class="w-24 text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
              />
              <select
                v-model="actionForm.delay_type"
                class="flex-1 text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
              >
                <option value="minutes">Minutos</option>
                <option value="hours">Horas</option>
                <option value="days">Dias corridos</option>
                <option value="business_days">Dias úteis</option>
              </select>
            </div>
            <p class="text-xs text-slate-400 mt-1">
              {{
                !actionForm.delay_minutes
                  ? 'Executar imediatamente ao entrar na etapa'
                  : `Executar ${actionForm.delay_minutes} ${actionForm.delay_type} após entrar na etapa`
              }}
            </p>
          </div>

          <!-- WhatsApp -->
          <template v-if="actionForm.action_type === 'send_whatsapp'">
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Canal (Inbox)</label
              >
              <select
                v-model="actionForm.config.inbox_id"
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
              >
                <option :value="undefined">Qualquer canal disponível</option>
                <option
                  v-for="inbox in inboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
            </div>
            <div>
              <label class="flex items-center gap-2 cursor-pointer mb-2">
                <input
                  v-model="actionForm.config.use_ai"
                  type="checkbox"
                  class="rounded border-slate-300 text-violet-600"
                />
                <span
                  class="text-xs font-medium text-slate-600 dark:text-slate-300"
                  >Gerar mensagem com IA</span
                >
              </label>
              <div v-if="actionForm.config.use_ai">
                <label class="text-xs text-slate-500 mb-1 block"
                  >Instrução para IA</label
                >
                <textarea
                  v-model="actionForm.config.ai_prompt"
                  rows="2"
                  placeholder="Ex: Follow-up gentil sobre a proposta"
                  class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30 resize-none"
                />
              </div>
              <div v-else>
                <label class="text-xs text-slate-500 mb-1 block"
                  >Mensagem</label
                >
                <textarea
                  v-model="actionForm.config.message"
                  rows="4"
                  placeholder="Digite a mensagem... Use {{nome}}, {{telefone}}"
                  class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30 resize-none"
                />
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Janela de envio (horário)</label
              >
              <div class="flex items-center gap-2">
                <input
                  v-model="actionForm.config.business_hours_start"
                  type="time"
                  class="flex-1 text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                />
                <span class="text-xs text-slate-400">até</span>
                <input
                  v-model="actionForm.config.business_hours_end"
                  type="time"
                  class="flex-1 text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                />
              </div>
              <p class="text-xs text-slate-400 mt-1">
                Deixe vazio para enviar a qualquer hora
              </p>
            </div>
          </template>

          <!-- Webhook -->
          <template v-if="actionForm.action_type === 'send_webhook'">
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >URL</label
              >
              <input
                v-model="actionForm.config.url"
                type="url"
                placeholder="https://seu-sistema.com/webhook"
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Método</label
              >
              <select
                v-model="actionForm.config.method"
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
              >
                <option value="POST">POST</option>
                <option value="GET">GET</option>
                <option value="PUT">PUT</option>
                <option value="PATCH">PATCH</option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Payload (JSON)</label
              >
              <textarea
                v-model="actionForm.config.payload"
                rows="4"
                placeholder='{"key": "value"}'
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30 resize-none font-mono"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Headers (JSON)</label
              >
              <textarea
                v-model="actionForm.config.headers"
                rows="2"
                placeholder='{"Authorization": "Bearer token"}'
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30 resize-none font-mono"
              />
            </div>
          </template>

          <!-- Task -->
          <template v-if="actionForm.action_type === 'create_task'">
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Título da tarefa</label
              >
              <input
                v-model="actionForm.config.title"
                type="text"
                placeholder="Ex: Ligar para o cliente"
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Descrição</label
              >
              <textarea
                v-model="actionForm.config.description"
                rows="2"
                placeholder="Detalhes..."
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30 resize-none"
              />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                  >Responsável</label
                >
                <select
                  v-model="actionForm.config.assignee_id"
                  class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                >
                  <option :value="undefined">Sem responsável</option>
                  <option
                    v-for="agent in agents"
                    :key="agent.id"
                    :value="agent.id"
                  >
                    {{ agent.name }}
                  </option>
                </select>
              </div>
              <div>
                <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                  >Prioridade</label
                >
                <select
                  v-model="actionForm.config.priority"
                  class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                >
                  <option value="low">Baixa</option>
                  <option value="medium">Média</option>
                  <option value="high">Alta</option>
                </select>
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-slate-500 mb-1.5 block"
                >Prazo (horas após entrada na etapa)</label
              >
              <input
                v-model.number="actionForm.config.due_hours"
                type="number"
                min="0"
                placeholder="24"
                class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
              />
            </div>
          </template>

          <!-- Active -->
          <label class="flex items-center gap-2.5 cursor-pointer pt-1">
            <input
              v-model="actionForm.active"
              type="checkbox"
              class="rounded border-slate-300 text-violet-600 focus:ring-violet-500"
            />
            <span class="text-xs font-medium text-slate-600 dark:text-slate-300"
              >Atividade ativa</span
            >
          </label>
        </div>

        <!-- Footer -->
        <div
          class="flex gap-2 px-5 py-4 border-t border-slate-100 dark:border-slate-800"
        >
          <button
            :disabled="actionFormSaving"
            class="flex-1 text-xs py-2.5 rounded-xl bg-violet-600 text-white hover:bg-violet-700 font-medium transition-colors disabled:opacity-50"
            @click="saveAction"
          >
            {{
              actionFormSaving
                ? 'Salvando...'
                : actionFormEditing
                  ? 'Salvar alterações'
                  : 'Adicionar atividade'
            }}
          </button>
          <button
            class="text-xs px-4 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800"
            @click="closeActionForm"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
