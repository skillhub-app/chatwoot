<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import KanbanColumn from './KanbanColumn.vue';
import KanbanCardModal from './KanbanCardModal.vue';
import KanbanPipelineModal from './KanbanPipelineModal.vue';

const router = useRouter();

const store = useStore();

// UI state
const selectedItem = ref(null);
const showAddCardModal = ref(false);
const addCardStage = ref(null);
const newCardTitle = ref('');
const newCardPhone = ref('');
const newCardValue = ref('');
const showPipelineModal = ref(false);
const editingPipeline = ref(null);
const showPipelineDropdown = ref(false);
const showFilters = ref(false);

// Filters state
const filterSearch = ref('');
const filterSource = ref('');
const filterTemperature = ref('');
const filterStatus = ref('');
const filterCreatedFrom = ref('');
const filterCreatedTo = ref('');
const filterCloseDateFrom = ref('');
const filterCloseDateTo = ref('');
const filterValueMin = ref('');
const filterValueMax = ref('');

// Store
const pipelines = computed(() => store.getters['kanban/getPipelines']);
const activePipelineId = computed(
  () => store.getters['kanban/getActivePipelineId']
);
const activePipeline = computed(
  () => store.getters['kanban/getActivePipeline']
);
const stages = computed(() => store.getters['kanban/getStages']);
const allItems = computed(() => store.getters['kanban/getItems']);
const uiFlags = computed(() => store.getters['kanban/getUIFlags']);
const isLoading = computed(
  () =>
    uiFlags.value.isFetchingPipelines ||
    uiFlags.value.isFetchingStages ||
    uiFlags.value.isFetchingItems
);

// Pipeline summary stats
const pipelineSummary = computed(() => {
  const open = allItems.value.filter(i => !i.won_at && !i.lost_at);
  const totalValue = open.reduce((s, i) => s + (parseFloat(i.value) || 0), 0);
  const avgTicket = open.length > 0 ? totalValue / open.length : 0;
  return {
    count: open.length,
    totalValue,
    stages: stages.value.length,
    avgTicket,
  };
});

function formatBRL(val) {
  if (!val) return 'R$ 0';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(val);
}

const activeFiltersCount = computed(() => {
  let count = 0;
  if (filterSearch.value) count++;
  if (filterSource.value) count++;
  if (filterTemperature.value) count++;
  if (filterStatus.value) count++;
  if (filterCreatedFrom.value) count++;
  if (filterCreatedTo.value) count++;
  if (filterCloseDateFrom.value) count++;
  if (filterCloseDateTo.value) count++;
  if (filterValueMin.value) count++;
  if (filterValueMax.value) count++;
  return count;
});

async function loadBoard(pipelineId) {
  const filters = {};
  if (filterSearch.value) filters.search = filterSearch.value;
  if (filterSource.value) filters.source = filterSource.value;
  if (filterTemperature.value) filters.temperature = filterTemperature.value;
  if (filterStatus.value) filters.status = filterStatus.value;
  if (filterCreatedFrom.value) filters.created_from = filterCreatedFrom.value;
  if (filterCreatedTo.value) filters.created_to = filterCreatedTo.value;
  if (filterCloseDateFrom.value)
    filters.close_date_from = filterCloseDateFrom.value;
  if (filterCloseDateTo.value) filters.close_date_to = filterCloseDateTo.value;
  if (filterValueMin.value) filters.value_min = filterValueMin.value;
  if (filterValueMax.value) filters.value_max = filterValueMax.value;
  await Promise.all([
    store.dispatch('kanban/fetchStages', pipelineId),
    store.dispatch('kanban/fetchItems', { pipelineId, filters }),
  ]);
}

watch(activePipelineId, id => {
  if (id) loadBoard(id);
});
watch(
  [
    filterSearch,
    filterSource,
    filterTemperature,
    filterStatus,
    filterCreatedFrom,
    filterCreatedTo,
    filterCloseDateFrom,
    filterCloseDateTo,
    filterValueMin,
    filterValueMax,
  ],
  () => {
    if (activePipelineId.value) loadBoard(activePipelineId.value);
  }
);

onMounted(async () => {
  await store.dispatch('kanban/fetchPipelines');
  if (activePipelineId.value) loadBoard(activePipelineId.value);
});

function openAddCard(stage) {
  addCardStage.value = stage;
  newCardTitle.value = '';
  newCardPhone.value = '';
  newCardValue.value = '';
  showAddCardModal.value = true;
}

async function confirmAddCard() {
  if (!newCardTitle.value.trim()) return;
  await store.dispatch('kanban/createItem', {
    pipelineId: activePipelineId.value,
    stage_id: addCardStage.value.id,
    title: newCardTitle.value.trim(),
    contact_phone: newCardPhone.value.trim() || undefined,
    value: newCardValue.value || undefined,
  });
  showAddCardModal.value = false;
}

function selectPipeline(id) {
  store.dispatch('kanban/setActivePipeline', id);
  showPipelineDropdown.value = false;
}

function openCreatePipeline() {
  editingPipeline.value = null;
  showPipelineModal.value = true;
  showPipelineDropdown.value = false;
}

function openEditPipeline() {
  editingPipeline.value = activePipeline.value;
  showPipelineModal.value = true;
}

function clearFilters() {
  filterSearch.value = '';
  filterSource.value = '';
  filterTemperature.value = '';
  filterStatus.value = '';
  filterCreatedFrom.value = '';
  filterCreatedTo.value = '';
  filterCloseDateFrom.value = '';
  filterCloseDateTo.value = '';
  filterValueMin.value = '';
  filterValueMax.value = '';
}
</script>

<template>
  <div
    class="flex flex-col flex-1 h-full min-h-0 bg-white dark:bg-slate-900 overflow-hidden"
    @click="showPipelineDropdown = false"
  >
    <!-- Top bar -->
    <div
      class="flex items-center gap-3 px-5 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0 flex-wrap"
    >
      <div class="flex items-center gap-2">
        <span class="i-lucide-kanban size-5 text-woot-500" />
        <h1 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          Kanban
        </h1>
      </div>

      <!-- Pipeline dropdown -->
      <div class="relative" @click.stop>
        <button
          class="flex items-center gap-2 text-sm px-3 py-1.5 rounded-lg border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 hover:border-woot-400 transition-colors font-medium"
          @click="showPipelineDropdown = !showPipelineDropdown"
        >
          <span class="i-lucide-layers size-3.5 text-woot-500" />
          {{ activePipeline?.name || 'Selecionar Pipeline' }}
          <span class="i-lucide-chevron-down size-3.5 text-slate-400" />
        </button>

        <div
          v-if="showPipelineDropdown"
          class="absolute top-full left-0 mt-1 z-40 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-xl w-56 overflow-hidden"
        >
          <div v-if="pipelines.length" class="py-1">
            <button
              v-for="p in pipelines"
              :key="p.id"
              class="w-full flex items-center justify-between px-3 py-2 text-sm hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
              :class="
                p.id === activePipelineId
                  ? 'text-woot-600 font-medium'
                  : 'text-slate-700 dark:text-slate-200'
              "
              @click="selectPipeline(p.id)"
            >
              <span>{{ p.name }}</span>
              <span
                v-if="p.id === activePipelineId"
                class="i-lucide-check size-3.5 text-woot-500"
              />
            </button>
          </div>
          <div v-else class="px-3 py-2 text-xs text-slate-400">
            Nenhuma pipeline
          </div>
          <div class="border-t border-slate-100 dark:border-slate-700 py-1">
            <button
              class="w-full flex items-center gap-2 px-3 py-2 text-sm text-woot-600 hover:bg-woot-50 dark:hover:bg-woot-900/30 transition-colors font-medium"
              @click="openCreatePipeline"
            >
              <span class="i-lucide-plus size-3.5" />
              Nova Pipeline
            </button>
          </div>
        </div>
      </div>

      <!-- Filter toggle -->
      <button
        class="relative flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border transition-colors font-medium"
        :class="
          activeFiltersCount > 0
            ? 'border-woot-400 bg-woot-50 dark:bg-woot-900/30 text-woot-600'
            : 'border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-50'
        "
        @click="showFilters = !showFilters"
      >
        <span class="i-lucide-filter size-3.5" />
        Filtros
        <span
          v-if="activeFiltersCount > 0"
          class="size-4 rounded-full bg-woot-500 text-white text-[10px] font-bold flex items-center justify-center"
        >
          {{ activeFiltersCount }}
        </span>
      </button>

      <!-- Actions right -->
      <div class="ml-auto flex items-center gap-2">
        <span
          v-if="isLoading"
          class="i-lucide-loader-circle size-4 animate-spin text-woot-500"
        />
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400 hover:bg-amber-100 dark:hover:bg-amber-900/40 font-medium transition-colors border border-amber-200 dark:border-amber-700"
          @click="router.push({ name: 'kanban_gamification' })"
        >
          <span class="i-lucide-trophy size-3.5" />
          Ranking
        </button>
        <button
          v-if="activePipeline"
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700 font-medium transition-colors"
          @click="openEditPipeline"
        >
          <span class="i-lucide-settings size-3.5" />
          Configurações
        </button>
      </div>
    </div>

    <!-- Filter panel -->
    <div
      v-if="showFilters"
      class="border-b border-slate-100 dark:border-slate-800 bg-slate-50 dark:bg-slate-900/50"
    >
      <!-- Search -->
      <div class="px-5 pt-3 pb-2">
        <div class="relative">
          <span
            class="absolute left-3 top-1/2 -translate-y-1/2 i-lucide-search size-4 text-slate-400"
          />
          <input
            v-model="filterSearch"
            type="text"
            placeholder="Buscar por nome ou telefone..."
            class="w-full text-sm pl-9 pr-3 py-2 border border-slate-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
      </div>

      <!-- Filter rows -->
      <div class="px-5 pb-3 grid grid-cols-2 md:grid-cols-4 gap-2">
        <select
          v-model="filterSource"
          class="text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2.5 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-woot-500"
        >
          <option value="">Origem: todas</option>
          <option value="whatsapp">WhatsApp</option>
          <option value="instagram">Instagram</option>
          <option value="facebook">Facebook</option>
          <option value="website">Website</option>
          <option value="phone">Telefone</option>
          <option value="email">E-mail</option>
          <option value="referral">Indicação</option>
          <option value="manual">Manual</option>
        </select>

        <select
          v-model="filterTemperature"
          class="text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2.5 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-woot-500"
        >
          <option value="">Temperatura: todas</option>
          <option value="cold">❄️ Frio</option>
          <option value="warm">🌡 Morno</option>
          <option value="hot">🔥 Quente</option>
          <option value="very_hot">💥 Muito Quente</option>
        </select>

        <select
          v-model="filterStatus"
          class="text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2.5 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-woot-500"
        >
          <option value="">Status: todos</option>
          <option value="open">Aberto</option>
          <option value="won">Ganho</option>
          <option value="lost">Perdido</option>
        </select>

        <div class="flex gap-1.5">
          <input
            v-model="filterValueMin"
            type="number"
            min="0"
            placeholder="Valor mín"
            class="flex-1 text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
          <input
            v-model="filterValueMax"
            type="number"
            min="0"
            placeholder="Valor máx"
            class="flex-1 text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <div>
          <p class="text-[10px] text-slate-400 mb-1">Criado de</p>
          <input
            v-model="filterCreatedFrom"
            type="date"
            class="w-full text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none"
          />
        </div>
        <div>
          <p class="text-[10px] text-slate-400 mb-1">Criado até</p>
          <input
            v-model="filterCreatedTo"
            type="date"
            class="w-full text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none"
          />
        </div>
        <div>
          <p class="text-[10px] text-slate-400 mb-1">Fechamento de</p>
          <input
            v-model="filterCloseDateFrom"
            type="date"
            class="w-full text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none"
          />
        </div>
        <div>
          <p class="text-[10px] text-slate-400 mb-1">Fechamento até</p>
          <input
            v-model="filterCloseDateTo"
            type="date"
            class="w-full text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none"
          />
        </div>
      </div>

      <div
        v-if="activeFiltersCount > 0"
        class="px-5 pb-2.5 flex items-center gap-2"
      >
        <span class="text-xs text-slate-500"
          >{{ activeFiltersCount }} filtro(s) ativo(s)</span
        >
        <button
          class="flex items-center gap-1 text-xs text-red-500 hover:text-red-700 font-medium"
          @click="clearFilters"
        >
          <span class="i-lucide-x size-3" />
          Limpar tudo
        </button>
      </div>
    </div>

    <!-- Pipeline Summary Bar -->
    <div
      v-if="stages.length && allItems.length > 0"
      class="flex items-stretch divide-x divide-slate-200 dark:divide-slate-700 border-b border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-900/50 shrink-0"
    >
      <div class="flex flex-col px-5 py-2.5">
        <span class="text-[10px] text-slate-400 uppercase tracking-wide mb-0.5"
          >Negócios no Funil</span
        >
        <span class="text-lg font-bold text-slate-800 dark:text-slate-100">{{
          pipelineSummary.count
        }}</span>
      </div>
      <div class="flex flex-col px-5 py-2.5">
        <span class="text-[10px] text-slate-400 uppercase tracking-wide mb-0.5"
          >Valor Total</span
        >
        <span class="text-lg font-bold text-woot-600 dark:text-woot-400">{{
          formatBRL(pipelineSummary.totalValue)
        }}</span>
      </div>
      <div class="flex flex-col px-5 py-2.5">
        <span class="text-[10px] text-slate-400 uppercase tracking-wide mb-0.5"
          >Etapas</span
        >
        <span class="text-lg font-bold text-slate-800 dark:text-slate-100">{{
          pipelineSummary.stages
        }}</span>
      </div>
      <div class="flex flex-col px-5 py-2.5">
        <span class="text-[10px] text-slate-400 uppercase tracking-wide mb-0.5"
          >Ticket Médio</span
        >
        <span class="text-lg font-bold text-green-600 dark:text-green-400">{{
          formatBRL(pipelineSummary.avgTicket)
        }}</span>
      </div>
    </div>

    <!-- Board -->
    <div class="flex-1 min-h-0 overflow-x-auto overflow-y-hidden">
      <!-- Columns -->
      <div v-if="stages.length" class="flex gap-3 p-4 h-full items-stretch">
        <KanbanColumn
          v-for="stage in stages"
          :key="stage.id"
          :stage="stage"
          :pipeline-id="activePipelineId"
          @card-click="selectedItem = $event"
          @add-card="openAddCard"
        />
      </div>

      <!-- Empty: has pipeline but no stages -->
      <div
        v-else-if="!isLoading && activePipeline"
        class="flex flex-col items-center justify-center h-full text-center px-6"
      >
        <span
          class="i-lucide-layout-dashboard size-14 text-slate-300 dark:text-slate-600 mb-4"
        />
        <p
          class="text-sm font-semibold text-slate-700 dark:text-slate-200 mb-1"
        >
          Nenhuma etapa em "{{ activePipeline.name }}"
        </p>
        <p class="text-xs text-slate-400 dark:text-slate-500 mb-4">
          Configure as etapas do seu pipeline para começar a usar o Kanban.
        </p>
        <button
          class="flex items-center gap-2 text-sm px-4 py-2 rounded-lg bg-woot-500 text-white hover:bg-woot-600 font-medium transition-colors shadow-sm"
          @click="openEditPipeline"
        >
          <span class="i-lucide-settings size-4" />
          Configurar etapas
        </button>
      </div>

      <!-- Empty: no pipelines at all -->
      <div
        v-else-if="!isLoading && !pipelines.length"
        class="flex flex-col items-center justify-center h-full text-center px-6"
      >
        <span
          class="i-lucide-kanban size-16 text-slate-300 dark:text-slate-600 mb-4"
        />
        <p
          class="text-base font-semibold text-slate-700 dark:text-slate-200 mb-1"
        >
          Bem-vindo ao Kanban
        </p>
        <p class="text-sm text-slate-400 dark:text-slate-500 mb-6 max-w-sm">
          Organize seus leads e oportunidades em pipelines visuais. Crie sua
          primeira pipeline para começar.
        </p>
        <button
          class="flex items-center gap-2 text-sm px-5 py-2.5 rounded-lg bg-woot-500 text-white hover:bg-woot-600 font-semibold transition-colors shadow-md"
          @click="openCreatePipeline"
        >
          <span class="i-lucide-plus size-4" />
          Criar primeira Pipeline
        </button>
      </div>
    </div>

    <!-- Card detail modal -->
    <KanbanCardModal
      :item="selectedItem"
      :pipeline-id="activePipelineId"
      @close="selectedItem = null"
      @updated="selectedItem = null"
    />

    <!-- Pipeline create/edit modal -->
    <KanbanPipelineModal
      v-if="showPipelineModal"
      :pipeline="editingPipeline"
      @close="showPipelineModal = false"
      @saved="showPipelineModal = false"
    />

    <!-- Add card modal -->
    <div
      v-if="showAddCardModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      @click.self="showAddCardModal = false"
    >
      <div
        class="bg-white dark:bg-slate-800 rounded-xl shadow-xl w-full max-w-sm mx-4"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-slate-100 dark:border-slate-700"
        >
          <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
            Novo card em
            <span class="text-woot-500">{{ addCardStage?.name }}</span>
          </h3>
          <button
            class="text-slate-400 hover:text-slate-600"
            @click="showAddCardModal = false"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
        <div class="px-5 py-4 space-y-3">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
              >Título *</label
            >
            <input
              v-model="newCardTitle"
              type="text"
              placeholder="Nome do lead ou oportunidade"
              class="w-full text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              autofocus
              @keyup.enter="confirmAddCard"
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
                >Valor (R$)</label
              >
              <input
                v-model="newCardValue"
                type="number"
                min="0"
                step="0.01"
                placeholder="0,00"
                class="w-full text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              />
            </div>
            <div>
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
                >Telefone</label
              >
              <input
                v-model="newCardPhone"
                type="text"
                placeholder="+55..."
                class="w-full text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              />
            </div>
          </div>
        </div>
        <div
          class="px-5 py-3 bg-slate-50 dark:bg-slate-900 flex justify-end gap-2 rounded-b-xl"
        >
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-slate-300 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-700 font-medium transition-colors"
            @click="showAddCardModal = false"
          >
            Cancelar
          </button>
          <button
            :disabled="!newCardTitle.trim() || uiFlags.isCreating"
            class="text-xs px-3 py-1.5 rounded-lg bg-woot-500 text-white hover:bg-woot-600 font-medium transition-colors disabled:opacity-50"
            @click="confirmAddCard"
          >
            Criar card
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
