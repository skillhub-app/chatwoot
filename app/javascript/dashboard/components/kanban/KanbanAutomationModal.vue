<!-- eslint-disable vue/no-bare-strings-in-template, vue/max-attributes-per-line, prettier/prettier -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { automationsAPI } from 'dashboard/api/kanban.js';

const props = defineProps({
  pipeline: { type: Object, required: true },
});
const emit = defineEmits(['close']);

const store = useStore();
const stages = computed(() => store.getters['kanban/getStages'] || []);

const automations = ref([]);
const loading = ref(false);
const saving = ref(false);
const error = ref(null);

const selectedStageId = ref(null);
const selectedAutomation = ref(null);
const showActionForm = ref(false);
const editingAction = ref(null);

const ACTION_TYPES = [
  {
    value: 'send_whatsapp',
    label: 'Enviar WhatsApp',
    icon: 'i-lucide-message-circle',
  },
  {
    value: 'send_webhook',
    label: 'Disparar Webhook',
    icon: 'i-lucide-webhook',
  },
  {
    value: 'create_task',
    label: 'Criar Tarefa',
    icon: 'i-lucide-check-square',
  },
];

const DELAY_TYPES = [
  { value: 'minutes', label: 'minutos' },
  { value: 'hours', label: 'horas' },
  { value: 'days', label: 'dias' },
  { value: 'business_days', label: 'dias úteis' },
];

const blankAutomation = () => ({
  id: null,
  pipeline_id: props.pipeline.id,
  trigger_stage_id: null,
  name: '',
  description: '',
  active: true,
  stop_on_reply: true,
  stop_on_stage_change: true,
  stop_on_human_takeover: false,
  actions: [],
});

const blankAction = () => ({
  id: null,
  action_type: 'send_whatsapp',
  position: 0,
  delay_minutes: 0,
  delay_type: 'minutes',
  active: true,
  config: {},
});

const automationForm = ref(blankAutomation());
const actionForm = ref(blankAction());

async function loadAutomations() {
  loading.value = true;
  error.value = null;
  try {
    const res = await automationsAPI.list({ pipeline_id: props.pipeline.id });
    automations.value = res.data.payload || [];
  } catch (e) {
    error.value = 'Erro ao carregar automações';
  } finally {
    loading.value = false;
  }
}

function stageAutomations(stageId) {
  return automations.value.filter(a => a.trigger_stage_id === stageId);
}

function selectStage(stageId) {
  selectedStageId.value = stageId;
  selectedAutomation.value = null;
  showActionForm.value = false;
}

function newAutomation(stageId) {
  automationForm.value = {
    ...blankAutomation(),
    trigger_stage_id: stageId,
    name: `Automação - ${stages.value.find(s => s.id === stageId)?.name || ''}`,
  };
  selectedAutomation.value = null;
  showActionForm.value = false;
}

function editAutomation(automation) {
  automationForm.value = { ...automation };
  selectedAutomation.value = automation;
  showActionForm.value = false;
}

async function saveAutomation() {
  saving.value = true;
  error.value = null;
  try {
    const data = {
      pipeline_id: automationForm.value.pipeline_id,
      trigger_stage_id: automationForm.value.trigger_stage_id,
      name: automationForm.value.name,
      description: automationForm.value.description,
      active: automationForm.value.active,
      stop_on_reply: automationForm.value.stop_on_reply,
      stop_on_stage_change: automationForm.value.stop_on_stage_change,
      stop_on_human_takeover: automationForm.value.stop_on_human_takeover,
    };
    if (automationForm.value.id) {
      await automationsAPI.update(automationForm.value.id, data);
    } else {
      await automationsAPI.create(data);
    }
    await loadAutomations();
    automationForm.value = blankAutomation();
    selectedAutomation.value = null;
  } catch (e) {
    error.value = 'Erro ao salvar automação';
  } finally {
    saving.value = false;
  }
}

async function deleteAutomation(automation) {
  if (!window.confirm(`Excluir a automação "${automation.name}"?`)) return;
  try {
    await automationsAPI.delete(automation.id);
    await loadAutomations();
    if (selectedAutomation.value?.id === automation.id) {
      selectedAutomation.value = null;
      automationForm.value = blankAutomation();
    }
  } catch (e) {
    error.value = 'Erro ao excluir automação';
  }
}

function newAction(automation) {
  selectedAutomation.value = automation;
  editingAction.value = null;
  actionForm.value = {
    ...blankAction(),
    position: automation.actions?.length || 0,
  };
  showActionForm.value = true;
}

function editAction(automation, action) {
  selectedAutomation.value = automation;
  editingAction.value = action;
  actionForm.value = { ...action, config: { ...action.config } };
  showActionForm.value = true;
}

async function saveAction() {
  saving.value = true;
  error.value = null;
  try {
    const data = {
      action_type: actionForm.value.action_type,
      position: actionForm.value.position,
      delay_minutes: actionForm.value.delay_minutes,
      delay_type: actionForm.value.delay_type,
      active: actionForm.value.active,
      config: actionForm.value.config,
    };
    if (actionForm.value.id) {
      await automationsAPI.updateAction(
        selectedAutomation.value.id,
        actionForm.value.id,
        data
      );
    } else {
      await automationsAPI.createAction(selectedAutomation.value.id, data);
    }
    await loadAutomations();
    showActionForm.value = false;
    editingAction.value = null;
    const updated = automations.value.find(
      a => a.id === selectedAutomation.value.id
    );
    if (updated) selectedAutomation.value = updated;
  } catch (e) {
    error.value = 'Erro ao salvar ação';
  } finally {
    saving.value = false;
  }
}

async function deleteAction(automation, action) {
  try {
    await automationsAPI.deleteAction(automation.id, action.id);
    await loadAutomations();
    const updated = automations.value.find(a => a.id === automation.id);
    if (updated) selectedAutomation.value = updated;
  } catch (e) {
    error.value = 'Erro ao excluir ação';
  }
}

function actionTypeLabel(type) {
  return ACTION_TYPES.find(t => t.value === type)?.label || type;
}

function actionTypeIcon(type) {
  return ACTION_TYPES.find(t => t.value === type)?.icon || 'i-lucide-zap';
}

function delayLabel(action) {
  if (!action.delay_minutes && action.delay_type === 'minutes')
    return 'Imediato';
  const type =
    DELAY_TYPES.find(t => t.value === action.delay_type)?.label ||
    action.delay_type;
  return `${action.delay_minutes} ${type}`;
}

function onActionTypeChange() {
  actionForm.value.config = {};
}

onMounted(loadAutomations);
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm"
  >
    <div
      class="bg-white dark:bg-slate-900 rounded-2xl shadow-2xl w-full max-w-5xl mx-4 flex flex-col max-h-[90vh] overflow-hidden"
    >
      <!-- Header -->
      <div
        class="flex items-center justify-between px-6 py-4 border-b border-slate-100 dark:border-slate-800 shrink-0"
      >
        <div class="flex items-center gap-3">
          <div
            class="w-8 h-8 rounded-lg bg-violet-100 dark:bg-violet-900/30 flex items-center justify-center"
          >
            <span
              class="i-lucide-zap size-4 text-violet-600 dark:text-violet-400"
            />
          </div>
          <div>
            <h2
              class="text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              Automação de CRM
            </h2>
            <p class="text-xs text-slate-500 dark:text-slate-400">
              {{ pipeline.name }}
            </p>
          </div>
        </div>
        <button
          class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 p-1 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>

      <!-- Error -->
      <div
        v-if="error"
        class="mx-6 mt-3 text-xs text-red-600 bg-red-50 dark:bg-red-900/20 rounded-lg px-3 py-2 shrink-0"
      >
        {{ error }}
      </div>

      <!-- Body -->
      <div class="flex flex-1 min-h-0">
        <!-- Left: Stages list -->
        <div
          class="w-52 border-r border-slate-100 dark:border-slate-800 flex flex-col overflow-y-auto shrink-0"
        >
          <div
            class="px-3 py-3 text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wide"
          >
            Etapas
          </div>
          <div
            v-for="stage in stages"
            :key="stage.id"
            class="group flex items-center justify-between px-3 py-2.5 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
            :class="
              selectedStageId === stage.id
                ? 'bg-violet-50 dark:bg-violet-900/20 border-r-2 border-violet-500'
                : ''
            "
            @click="selectStage(stage.id)"
          >
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="w-2 h-2 rounded-full shrink-0"
                :style="stage.color ? `background:${stage.color}` : ''"
                :class="!stage.color ? 'bg-slate-400' : ''"
              />
              <span
                class="text-xs text-slate-700 dark:text-slate-300 truncate"
                >{{ stage.name }}</span
              >
            </div>
            <span
              v-if="stageAutomations(stage.id).length"
              class="text-xs bg-violet-100 dark:bg-violet-900/30 text-violet-600 dark:text-violet-400 rounded-full px-1.5 py-0.5 font-medium shrink-0"
            >
              {{ stageAutomations(stage.id).length }}
            </span>
          </div>
        </div>

        <!-- Middle: Automations for selected stage -->
        <div
          class="w-72 border-r border-slate-100 dark:border-slate-800 flex flex-col overflow-y-auto shrink-0"
        >
          <template v-if="selectedStageId">
            <div
              class="flex items-center justify-between px-4 py-3 border-b border-slate-100 dark:border-slate-800"
            >
              <span
                class="text-xs font-semibold text-slate-600 dark:text-slate-300"
              >
                {{ stages.find(s => s.id === selectedStageId)?.name }}
              </span>
              <button
                class="text-xs text-violet-600 dark:text-violet-400 hover:underline flex items-center gap-1"
                @click="newAutomation(selectedStageId)"
              >
                <span class="i-lucide-plus size-3" />
                Nova
              </button>
            </div>

            <div v-if="loading" class="flex items-center justify-center py-8">
              <span
                class="i-lucide-loader-2 size-5 text-slate-400 animate-spin"
              />
            </div>

            <div
              v-else-if="stageAutomations(selectedStageId).length === 0"
              class="px-4 py-8 text-center"
            >
              <span
                class="i-lucide-zap-off size-8 text-slate-300 dark:text-slate-600 mx-auto block mb-2"
              />
              <p class="text-xs text-slate-400 dark:text-slate-500">
                Nenhuma automação
              </p>
              <button
                class="mt-2 text-xs text-violet-600 hover:underline"
                @click="newAutomation(selectedStageId)"
              >
                Criar automação
              </button>
            </div>

            <div v-else class="divide-y divide-slate-100 dark:divide-slate-800">
              <div
                v-for="automation in stageAutomations(selectedStageId)"
                :key="automation.id"
                class="group px-4 py-3 hover:bg-slate-50 dark:hover:bg-slate-800/50 cursor-pointer"
                :class="
                  selectedAutomation?.id === automation.id
                    ? 'bg-slate-50 dark:bg-slate-800/50'
                    : ''
                "
                @click="editAutomation(automation)"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <div class="flex items-center gap-1.5 mb-1">
                      <span
                        class="w-1.5 h-1.5 rounded-full shrink-0"
                        :class="
                          automation.active ? 'bg-emerald-500' : 'bg-slate-300'
                        "
                      />
                      <span
                        class="text-xs font-medium text-slate-700 dark:text-slate-200 truncate"
                        >{{ automation.name }}</span
                      >
                    </div>
                    <span class="text-xs text-slate-400"
                      >{{ automation.actions?.length || 0 }} ações</span
                    >
                  </div>
                  <button
                    class="opacity-0 group-hover:opacity-100 text-slate-400 hover:text-red-500 p-0.5 rounded transition-all shrink-0"
                    @click.stop="deleteAutomation(automation)"
                  >
                    <span class="i-lucide-trash-2 size-3.5" />
                  </button>
                </div>
              </div>
            </div>
          </template>
          <div
            v-else
            class="flex flex-col items-center justify-center h-full py-12 px-4 text-center"
          >
            <span
              class="i-lucide-mouse-pointer-click size-8 text-slate-300 dark:text-slate-600 mb-2"
            />
            <p class="text-xs text-slate-400 dark:text-slate-500">
              Selecione uma etapa
            </p>
          </div>
        </div>

        <!-- Right: Automation detail / Action form -->
        <div class="flex-1 flex flex-col overflow-y-auto">
          <!-- Automation form -->
          <template
            v-if="
              selectedAutomation !== null || automationForm.trigger_stage_id
            "
          >
            <div
              class="px-5 py-4 border-b border-slate-100 dark:border-slate-800 shrink-0"
            >
              <h3
                class="text-xs font-semibold text-slate-600 dark:text-slate-300 mb-3"
              >
                {{ automationForm.id ? 'Editar Automação' : 'Nova Automação' }}
              </h3>
              <div class="space-y-3">
                <div>
                  <label
                    class="text-xs text-slate-500 dark:text-slate-400 mb-1 block"
                    >Nome</label
                  >
                  <input
                    v-model="automationForm.name"
                    type="text"
                    placeholder="Nome da automação"
                    class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                  />
                </div>
                <div>
                  <label
                    class="text-xs text-slate-500 dark:text-slate-400 mb-1 block"
                    >Descrição</label
                  >
                  <input
                    v-model="automationForm.description"
                    type="text"
                    placeholder="Opcional"
                    class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                  />
                </div>
                <div class="grid grid-cols-2 gap-3">
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      v-model="automationForm.active"
                      type="checkbox"
                      class="rounded border-slate-300 text-violet-600 focus:ring-violet-500"
                    />
                    <span class="text-xs text-slate-600 dark:text-slate-300"
                      >Ativa</span
                    >
                  </label>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      v-model="automationForm.stop_on_reply"
                      type="checkbox"
                      class="rounded border-slate-300 text-violet-600 focus:ring-violet-500"
                    />
                    <span class="text-xs text-slate-600 dark:text-slate-300"
                      >Parar ao responder</span
                    >
                  </label>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      v-model="automationForm.stop_on_stage_change"
                      type="checkbox"
                      class="rounded border-slate-300 text-violet-600 focus:ring-violet-500"
                    />
                    <span class="text-xs text-slate-600 dark:text-slate-300"
                      >Parar ao mover etapa</span
                    >
                  </label>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      v-model="automationForm.stop_on_human_takeover"
                      type="checkbox"
                      class="rounded border-slate-300 text-violet-600 focus:ring-violet-500"
                    />
                    <span class="text-xs text-slate-600 dark:text-slate-300"
                      >Parar ao atender</span
                    >
                  </label>
                </div>
                <button
                  :disabled="saving"
                  class="w-full text-xs px-3 py-2 rounded-lg bg-violet-600 text-white hover:bg-violet-700 font-medium transition-colors disabled:opacity-50"
                  @click="saveAutomation"
                >
                  {{ saving ? 'Salvando...' : 'Salvar' }}
                </button>
              </div>
            </div>

            <!-- Actions list -->
            <div v-if="selectedAutomation" class="px-5 py-4 flex-1">
              <div class="flex items-center justify-between mb-3">
                <span
                  class="text-xs font-semibold text-slate-600 dark:text-slate-300"
                  >Ações</span
                >
                <button
                  class="text-xs text-violet-600 dark:text-violet-400 hover:underline flex items-center gap-1"
                  @click="newAction(selectedAutomation)"
                >
                  <span class="i-lucide-plus size-3" />
                  Adicionar
                </button>
              </div>

              <div
                v-if="selectedAutomation.actions?.length === 0"
                class="text-center py-6"
              >
                <p class="text-xs text-slate-400">Nenhuma ação configurada</p>
              </div>

              <div class="space-y-2">
                <div
                  v-for="action in selectedAutomation.actions"
                  :key="action.id"
                  class="group flex items-center gap-3 px-3 py-2.5 rounded-lg border border-slate-100 dark:border-slate-700 hover:border-violet-200 dark:hover:border-violet-700 transition-colors"
                  :class="!action.active ? 'opacity-50' : ''"
                >
                  <span
                    class="size-4 text-violet-500 shrink-0"
                    :class="[actionTypeIcon(action.action_type)]"
                  />
                  <div class="flex-1 min-w-0">
                    <div
                      class="text-xs font-medium text-slate-700 dark:text-slate-200"
                    >
                      {{ actionTypeLabel(action.action_type) }}
                    </div>
                    <div class="text-xs text-slate-400">
                      {{ delayLabel(action) }}
                    </div>
                  </div>
                  <div
                    class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    <button
                      class="p-1 rounded text-slate-400 hover:text-violet-600"
                      @click="editAction(selectedAutomation, action)"
                    >
                      <span class="i-lucide-pencil size-3.5" />
                    </button>
                    <button
                      class="p-1 rounded text-slate-400 hover:text-red-500"
                      @click="deleteAction(selectedAutomation, action)"
                    >
                      <span class="i-lucide-trash-2 size-3.5" />
                    </button>
                  </div>
                </div>
              </div>

              <!-- Inline action form -->
              <div
                v-if="showActionForm"
                class="mt-4 p-4 rounded-xl border border-violet-200 dark:border-violet-700 bg-violet-50 dark:bg-violet-900/10"
              >
                <h4
                  class="text-xs font-semibold text-slate-700 dark:text-slate-200 mb-3"
                >
                  {{ editingAction ? 'Editar Ação' : 'Nova Ação' }}
                </h4>
                <div class="space-y-3">
                  <div>
                    <label class="text-xs text-slate-500 mb-1 block"
                      >Tipo</label
                    >
                    <select
                      v-model="actionForm.action_type"
                      class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                      @change="onActionTypeChange"
                    >
                      <option
                        v-for="t in ACTION_TYPES"
                        :key="t.value"
                        :value="t.value"
                      >
                        {{ t.label }}
                      </option>
                    </select>
                  </div>
                  <div class="flex gap-2">
                    <div class="flex-1">
                      <label class="text-xs text-slate-500 mb-1 block"
                        >Atraso</label
                      >
                      <input
                        v-model.number="actionForm.delay_minutes"
                        type="number"
                        min="0"
                        class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                      />
                    </div>
                    <div class="flex-1">
                      <label class="text-xs text-slate-500 mb-1 block"
                        >Unidade</label
                      >
                      <select
                        v-model="actionForm.delay_type"
                        class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                      >
                        <option
                          v-for="d in DELAY_TYPES"
                          :key="d.value"
                          :value="d.value"
                        >
                          {{ d.label }}
                        </option>
                      </select>
                    </div>
                  </div>

                  <!-- WhatsApp config -->
                  <template v-if="actionForm.action_type === 'send_whatsapp'">
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input
                        v-model="actionForm.config.use_ai"
                        type="checkbox"
                        class="rounded border-slate-300 text-violet-600"
                      />
                      <span class="text-xs text-slate-600 dark:text-slate-300"
                        >Usar IA para gerar mensagem</span
                      >
                    </label>
                    <div v-if="!actionForm.config.use_ai">
                      <label class="text-xs text-slate-500 mb-1 block"
                        >Mensagem</label
                      >
                      <textarea
                        v-model="actionForm.config.message"
                        rows="3"
                        placeholder="Texto da mensagem..."
                        class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30 resize-none"
                      />
                    </div>
                    <div v-else>
                      <label class="text-xs text-slate-500 mb-1 block"
                        >Instrução para IA</label
                      >
                      <input
                        v-model="actionForm.config.ai_prompt"
                        type="text"
                        placeholder="Ex: Faça um follow-up gentil sobre a proposta"
                        class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                      />
                    </div>
                    <div>
                      <label class="text-xs text-slate-500 mb-1 block"
                        >Horário de envio</label
                      >
                      <div class="flex gap-2">
                        <input
                          v-model="actionForm.config.business_hours_start"
                          type="time"
                          class="flex-1 text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                        />
                        <span class="text-xs text-slate-400 self-center"
                          >até</span
                        >
                        <input
                          v-model="actionForm.config.business_hours_end"
                          type="time"
                          class="flex-1 text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                        />
                      </div>
                    </div>
                  </template>

                  <!-- Webhook config -->
                  <template v-if="actionForm.action_type === 'send_webhook'">
                    <div>
                      <label class="text-xs text-slate-500 mb-1 block"
                        >URL do Webhook</label
                      >
                      <input
                        v-model="actionForm.config.url"
                        type="url"
                        placeholder="https://..."
                        class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                      />
                    </div>
                  </template>

                  <!-- Task config -->
                  <template v-if="actionForm.action_type === 'create_task'">
                    <div>
                      <label class="text-xs text-slate-500 mb-1 block"
                        >Título da Tarefa</label
                      >
                      <input
                        v-model="actionForm.config.title"
                        type="text"
                        placeholder="Ex: Ligar para o cliente"
                        class="w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                      />
                    </div>
                    <div>
                      <label class="text-xs text-slate-500 mb-1 block"
                        >Prazo (horas após criação)</label
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

                  <label class="flex items-center gap-2 cursor-pointer">
                    <input
                      v-model="actionForm.active"
                      type="checkbox"
                      class="rounded border-slate-300 text-violet-600"
                    />
                    <span class="text-xs text-slate-600 dark:text-slate-300"
                      >Ação ativa</span
                    >
                  </label>

                  <div class="flex gap-2">
                    <button
                      :disabled="saving"
                      class="flex-1 text-xs px-3 py-2 rounded-lg bg-violet-600 text-white hover:bg-violet-700 font-medium transition-colors disabled:opacity-50"
                      @click="saveAction"
                    >
                      {{ saving ? 'Salvando...' : 'Salvar ação' }}
                    </button>
                    <button
                      class="text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
                      @click="showActionForm = false"
                    >
                      Cancelar
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </template>

          <div
            v-else
            class="flex flex-col items-center justify-center h-full py-12 px-6 text-center"
          >
            <div
              class="w-12 h-12 rounded-2xl bg-violet-100 dark:bg-violet-900/30 flex items-center justify-center mb-3"
            >
              <span class="i-lucide-zap size-6 text-violet-500" />
            </div>
            <p
              class="text-sm font-medium text-slate-700 dark:text-slate-200 mb-1"
            >
              Automação de CRM
            </p>
            <p class="text-xs text-slate-400 dark:text-slate-500 max-w-xs">
              Selecione uma etapa e configure sequências automáticas de
              WhatsApp, webhooks e tarefas.
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
