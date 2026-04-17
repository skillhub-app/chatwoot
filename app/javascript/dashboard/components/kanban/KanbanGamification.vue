<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { gamificationAPI, goalsAPI } from 'dashboard/api/kanban';
import agentsAPI from 'dashboard/api/agents';

const router = useRouter();

// ── Data ──────────────────────────────────────────────────────────────
const loading = ref(true);
const rankings = ref([]);
const overview = ref(null);
const recentWins = ref([]);
const goals = ref([]);
const allAgents = ref([]);
const activeTab = ref('ranking');

// ── Settings Panel ────────────────────────────────────────────────────
const showSettings = ref(false);
const savingGoals = ref(false);
// Per-user goals being edited in settings panel (agentId -> { targetValue, targetWon })
const editableGoals = ref({});

// ── Month ─────────────────────────────────────────────────────────────
const now = new Date();
const currentYear = now.getFullYear();
const currentMonth = now.getMonth() + 1;
const monthName = now.toLocaleDateString('pt-BR', {
  month: 'long',
  year: 'numeric',
});

// ── Constants ─────────────────────────────────────────────────────────
const MEDALS = ['🥇', '🥈', '🥉'];
const PODIUM_BORDER = [
  'border-amber-400 shadow-amber-200 dark:shadow-amber-900/50',
  'border-slate-300 dark:border-slate-500',
  'border-amber-700 dark:border-amber-800',
];
const PODIUM_HEIGHTS = ['h-24', 'h-16', 'h-12'];
const PODIUM_COLORS = [
  'bg-amber-400 dark:bg-amber-600',
  'bg-slate-300 dark:bg-slate-500',
  'bg-amber-700 dark:bg-amber-800',
];

const CHALLENGES = [
  {
    id: 'first_win',
    icon: '🎯',
    label: 'Primeiro Ganho',
    desc: 'Feche seu primeiro negócio',
    condition: a => a.stats.won >= 1,
  },
  {
    id: 'five_wins',
    icon: '🔥',
    label: 'Closer',
    desc: 'Feche 5 negócios no mês',
    condition: a => a.stats.won >= 5,
  },
  {
    id: 'big_deal',
    icon: '💰',
    label: 'Big Deal',
    desc: 'Negócio acima de R$ 10.000',
    condition: a => a.stats.value >= 10000,
  },
  {
    id: 'converter',
    icon: '⚡',
    label: 'Conversor',
    desc: 'Conv. acima de 50%',
    condition: a => a.stats.conversion_rate >= 50,
  },
  {
    id: 'pipeline_king',
    icon: '👑',
    label: 'Líder do Mês',
    desc: 'Seja o #1 no ranking',
    condition: (a, all) => all[0]?.agent.id === a.agent.id,
  },
];

const BADGE_LEGEND = [
  { icon: '🎯', label: 'Primeiro Ganho', desc: '1+ fechamento' },
  { icon: '🔥', label: 'Closer', desc: '5+ fechamentos' },
  { icon: '💰', label: 'Big Deal', desc: 'R$ 10k+ em valor' },
  { icon: '⚡', label: 'Conversor', desc: 'Conv. ≥ 50%' },
  { icon: '👑', label: 'Líder', desc: '1º no ranking' },
];

// ── Load Data ─────────────────────────────────────────────────────────
async function loadData() {
  loading.value = true;
  try {
    const [r, o, w, g, agents] = await Promise.all([
      gamificationAPI.rankings(),
      gamificationAPI.overview(),
      gamificationAPI.recentWins(),
      goalsAPI.list(currentYear, currentMonth),
      agentsAPI.get(),
    ]);
    rankings.value = r.data.payload;
    overview.value = o.data.payload;
    recentWins.value = w.data.payload;
    goals.value = g.data.payload;
    allAgents.value = agents.data.payload || agents.data || [];
  } catch {
    /* ignore */
  } finally {
    loading.value = false;
  }
}

// ── Settings Panel ────────────────────────────────────────────────────
function openSettings() {
  // Populate editable goals from existing goals
  editableGoals.value = {};
  allAgents.value.forEach(agent => {
    const existing = goals.value.find(g => g.assignee_id === agent.id);
    editableGoals.value[agent.id] = {
      targetValue: existing?.target_value || '',
      targetWon: existing?.target_won || '',
    };
  });
  showSettings.value = true;
}

async function saveAllGoals() {
  savingGoals.value = true;
  try {
    const saves = Object.entries(editableGoals.value)
      .filter(
        ([, v]) =>
          parseFloat(v.targetValue) > 0 || parseInt(v.targetWon, 10) > 0
      )
      .map(([agentId, vals]) =>
        goalsAPI.upsert({
          assignee_id: parseInt(agentId, 10),
          year: currentYear,
          month: currentMonth,
          target_value: parseFloat(vals.targetValue) || 0,
          target_won: parseInt(vals.targetWon, 10) || 0,
        })
      );
    await Promise.all(saves);
    const g = await goalsAPI.list(currentYear, currentMonth);
    goals.value = g.data.payload;
    showSettings.value = false;
  } catch {
    /* ignore */
  } finally {
    savingGoals.value = false;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────
function getGoalFor(agentId) {
  return goals.value.find(g => g.assignee_id === agentId) || null;
}

function goalValuePct(agentId) {
  const goal = getGoalFor(agentId);
  if (!goal || !goal.target_value) return 0;
  const agent = rankings.value.find(r => r.agent.id === agentId);
  const val = agent?.stats.value || 0;
  return Math.min(100, Math.round((val / goal.target_value) * 100));
}

function goalWonPct(agentId) {
  const goal = getGoalFor(agentId);
  if (!goal || !goal.target_won) return 0;
  const agent = rankings.value.find(r => r.agent.id === agentId);
  const won = agent?.stats.won || 0;
  return Math.min(100, Math.round((won / goal.target_won) * 100));
}

function getBadges(agent, allRankings) {
  return CHALLENGES.filter(c => c.condition(agent, allRankings));
}

function formatCurrency(val) {
  if (!val) return 'R$ 0';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(val);
}

function formatDate(ts) {
  if (!ts) return '';
  return new Date(ts * 1000).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

// Total goals KPIs
const totalGoalValue = computed(() =>
  goals.value.reduce((s, g) => s + (parseFloat(g.target_value) || 0), 0)
);
const totalWonValue = computed(() =>
  rankings.value.reduce((s, a) => s + (a.stats.value || 0), 0)
);
const achievementPct = computed(() => {
  if (!totalGoalValue.value) return 0;
  return Math.min(
    100,
    Math.round((totalWonValue.value / totalGoalValue.value) * 100)
  );
});

onMounted(loadData);
</script>

<template>
  <div
    class="flex flex-col flex-1 h-full min-h-0 bg-slate-50 dark:bg-slate-900 overflow-hidden"
  >
    <!-- Header -->
    <div
      class="flex items-center justify-between px-6 py-3 bg-white dark:bg-slate-800 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <div class="flex items-center gap-3">
        <span class="text-2xl">🏆</span>
        <div>
          <h1 class="text-base font-bold text-slate-800 dark:text-slate-100">
            Gamificação & Ranking
          </h1>
          <p class="text-xs text-slate-500 dark:text-slate-400 capitalize">
            {{ monthName }}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          @click="router.push({ name: 'kanban_board' })"
        >
          <span class="i-lucide-arrow-left size-3.5" /> Voltar
        </button>
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          @click="loadData"
        >
          <span class="i-lucide-refresh-cw size-3.5" /> Atualizar
        </button>
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          @click="openSettings"
        >
          <span class="i-lucide-settings size-3.5" /> Configurações
        </button>
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-slate-800 dark:bg-slate-700 text-white hover:bg-slate-700 dark:hover:bg-slate-600 transition-colors"
          @click="
            () => {
              const r = router.resolve({ name: 'kanban_tv' });
              window.open(r.href, '_blank');
            }
          "
        >
          <span class="i-lucide-tv size-3.5" /> Modo TV
        </button>
      </div>
    </div>

    <!-- Tabs -->
    <div
      class="flex items-center gap-0 px-6 bg-white dark:bg-slate-800 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <button
        v-for="tab in [
          { id: 'ranking', label: 'Ranking', icon: 'i-lucide-trophy' },
          { id: 'metas', label: 'Metas Individuais', icon: 'i-lucide-target' },
          { id: 'wins', label: 'Últimas Vitórias', icon: 'i-lucide-star' },
          { id: 'badges', label: 'Badges', icon: 'i-lucide-award' },
        ]"
        :key="tab.id"
        class="flex items-center gap-1.5 px-4 py-3 text-xs font-medium border-b-2 transition-colors -mb-px"
        :class="
          activeTab === tab.id
            ? 'border-woot-500 text-woot-600 dark:text-woot-400'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300'
        "
        @click="activeTab = tab.id"
      >
        <span class="size-3.5" :class="[tab.icon]" />
        {{ tab.label }}
      </button>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center flex-1">
      <span class="i-lucide-loader-circle size-8 animate-spin text-woot-500" />
    </div>

    <!-- Main Content -->
    <div v-else class="flex-1 overflow-y-auto">
      <!-- ── RANKING TAB ── -->
      <div v-if="activeTab === 'ranking'" class="p-5 space-y-4">
        <!-- KPI bar -->
        <div v-if="overview" class="grid grid-cols-4 gap-3">
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4"
          >
            <p class="text-[10px] uppercase tracking-wide text-slate-400 mb-1">
              Total de Vendas
            </p>
            <p class="text-2xl font-bold text-slate-800 dark:text-slate-100">
              {{ overview.month.won }}
            </p>
            <p class="text-[10px] text-slate-400 mt-0.5">no mês</p>
          </div>
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4"
          >
            <p class="text-[10px] uppercase tracking-wide text-slate-400 mb-1">
              Faturamento
            </p>
            <p class="text-xl font-bold text-green-600 dark:text-green-400">
              {{ formatCurrency(overview.month.value) }}
            </p>
            <p class="text-[10px] text-slate-400 mt-0.5">no mês</p>
          </div>
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4"
          >
            <p class="text-[10px] uppercase tracking-wide text-slate-400 mb-1">
              Meta Mensal
            </p>
            <p class="text-xl font-bold text-amber-600 dark:text-amber-400">
              {{ formatCurrency(totalGoalValue) }}
            </p>
            <p class="text-[10px] text-slate-400 mt-0.5">objetivo total</p>
          </div>
          <div
            class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4"
          >
            <p class="text-[10px] uppercase tracking-wide text-slate-400 mb-1">
              % Atingimento
            </p>
            <p
              class="text-2xl font-bold"
              :class="
                achievementPct >= 100
                  ? 'text-green-600 dark:text-green-400'
                  : achievementPct >= 70
                    ? 'text-amber-600 dark:text-amber-400'
                    : 'text-red-500 dark:text-red-400'
              "
            >
              {{ achievementPct }}%
            </p>
            <div
              class="mt-1.5 h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
            >
              <div
                class="h-full rounded-full transition-all"
                :class="
                  achievementPct >= 100
                    ? 'bg-green-500'
                    : achievementPct >= 70
                      ? 'bg-amber-400'
                      : 'bg-red-400'
                "
                :style="{ width: achievementPct + '%' }"
              />
            </div>
          </div>
        </div>

        <!-- Podium -->
        <div
          v-if="rankings.length > 0"
          class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-6"
        >
          <h3
            class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-5 text-center"
          >
            Pódio do Mês
          </h3>
          <div class="flex items-end justify-center gap-4">
            <div
              v-if="rankings[1]"
              class="flex flex-col items-center gap-1.5 mb-1"
            >
              <img
                v-if="rankings[1].agent.avatar_url"
                :src="rankings[1].agent.avatar_url"
                class="size-12 rounded-full border-3 object-cover"
                :class="PODIUM_BORDER[1]"
              />
              <div
                v-else
                class="size-12 rounded-full bg-slate-200 dark:bg-slate-600 flex items-center justify-center text-xl border-3 font-bold"
                :class="PODIUM_BORDER[1]"
              >
                {{ rankings[1].agent.name.charAt(0) }}
              </div>
              <span
                class="text-xs font-semibold text-slate-700 dark:text-slate-200 max-w-[80px] truncate text-center"
                >{{ rankings[1].agent.name }}</span
              >
              <span class="text-xs text-slate-500"
                >{{ rankings[1].points }} pts</span
              >
              <div
                class="w-20 flex items-end justify-center pt-1 text-lg rounded-t-lg"
                :class="[PODIUM_COLORS[1], PODIUM_HEIGHTS[1]]"
              >
                🥈
              </div>
            </div>
            <div v-if="rankings[0]" class="flex flex-col items-center gap-1.5">
              <div class="text-2xl">👑</div>
              <img
                v-if="rankings[0].agent.avatar_url"
                :src="rankings[0].agent.avatar_url"
                class="size-16 rounded-full border-3 object-cover shadow-lg"
                :class="PODIUM_BORDER[0]"
              />
              <div
                v-else
                class="size-16 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center text-2xl border-3 font-bold"
                :class="PODIUM_BORDER[0]"
              >
                {{ rankings[0].agent.name.charAt(0) }}
              </div>
              <span
                class="text-sm font-bold text-slate-800 dark:text-slate-100 max-w-[100px] truncate text-center"
                >{{ rankings[0].agent.name }}</span
              >
              <span class="text-sm font-bold text-amber-600 dark:text-amber-400"
                >{{ rankings[0].points }} pts</span
              >
              <div
                class="w-20 flex items-end justify-center pt-1 text-xl rounded-t-lg"
                :class="[PODIUM_COLORS[0], PODIUM_HEIGHTS[0]]"
              >
                🥇
              </div>
            </div>
            <div
              v-if="rankings[2]"
              class="flex flex-col items-center gap-1.5 mb-1"
            >
              <img
                v-if="rankings[2].agent.avatar_url"
                :src="rankings[2].agent.avatar_url"
                class="size-12 rounded-full border-3 object-cover"
                :class="PODIUM_BORDER[2]"
              />
              <div
                v-else
                class="size-12 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center text-xl border-3 font-bold"
                :class="PODIUM_BORDER[2]"
              >
                {{ rankings[2].agent.name.charAt(0) }}
              </div>
              <span
                class="text-xs font-semibold text-slate-700 dark:text-slate-200 max-w-[80px] truncate text-center"
                >{{ rankings[2].agent.name }}</span
              >
              <span class="text-xs text-amber-700 dark:text-amber-500"
                >{{ rankings[2].points }} pts</span
              >
              <div
                class="w-20 flex items-end justify-center pt-1 text-lg rounded-t-lg"
                :class="[PODIUM_COLORS[2], PODIUM_HEIGHTS[2]]"
              >
                🥉
              </div>
            </div>
          </div>
        </div>

        <!-- Full ranking table -->
        <div
          class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 overflow-hidden"
        >
          <div
            class="px-4 py-3 border-b border-slate-100 dark:border-slate-700"
          >
            <h3
              class="text-xs font-semibold text-slate-600 dark:text-slate-300 uppercase tracking-wide"
            >
              Ranking Completo
            </h3>
          </div>
          <table class="w-full">
            <thead>
              <tr class="bg-slate-50 dark:bg-slate-700/50">
                <th
                  class="text-left px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  #
                </th>
                <th
                  class="text-left px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Agente
                </th>
                <th
                  class="text-right px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Ganhos
                </th>
                <th
                  class="text-right px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Faturado
                </th>
                <th
                  class="text-right px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Conv.
                </th>
                <th
                  class="text-right px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Pontos
                </th>
                <th
                  class="text-right px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Meta
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(agent, idx) in rankings"
                :key="agent.agent.id"
                class="border-b border-slate-50 dark:border-slate-700/50 last:border-0 hover:bg-slate-50 dark:hover:bg-slate-700/30 transition-colors"
              >
                <td class="px-4 py-3 w-10">
                  <span v-if="idx < 3" class="text-base">{{
                    MEDALS[idx]
                  }}</span>
                  <span v-else class="text-xs text-slate-400 font-semibold">{{
                    idx + 1
                  }}</span>
                </td>
                <td class="px-4 py-3">
                  <div class="flex items-center gap-2.5">
                    <img
                      v-if="agent.agent.avatar_url"
                      :src="agent.agent.avatar_url"
                      class="size-7 rounded-full object-cover"
                    />
                    <div
                      v-else
                      class="size-7 rounded-full bg-slate-200 dark:bg-slate-600 flex items-center justify-center text-xs font-bold text-slate-600 dark:text-slate-300"
                    >
                      {{ agent.agent.name.charAt(0).toUpperCase() }}
                    </div>
                    <div>
                      <p
                        class="text-xs font-semibold text-slate-800 dark:text-slate-100"
                      >
                        {{ agent.agent.name }}
                      </p>
                      <div class="flex gap-0.5 mt-0.5">
                        <span
                          v-for="badge in getBadges(agent, rankings)"
                          :key="badge.id"
                          class="text-[10px]"
                          :title="badge.label"
                          >{{ badge.icon }}</span
                        >
                      </div>
                    </div>
                  </div>
                </td>
                <td class="px-4 py-3 text-right">
                  <span
                    class="text-xs font-semibold text-green-600 dark:text-green-400"
                    >{{ agent.stats.won }}</span
                  >
                  <span class="text-[10px] text-slate-400">
                    /{{ agent.stats.total }}</span
                  >
                </td>
                <td
                  class="px-4 py-3 text-right text-xs font-medium text-slate-700 dark:text-slate-200"
                >
                  {{ formatCurrency(agent.stats.value) }}
                </td>
                <td class="px-4 py-3 text-right">
                  <span
                    class="text-xs"
                    :class="
                      agent.stats.conversion_rate >= 50
                        ? 'text-green-600 font-semibold'
                        : 'text-slate-500'
                    "
                  >
                    {{ agent.stats.conversion_rate }}%
                  </span>
                </td>
                <td class="px-4 py-3 text-right">
                  <div class="flex items-center justify-end gap-2">
                    <div
                      class="w-10 h-1.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
                    >
                      <div
                        class="h-full bg-amber-400 rounded-full"
                        :style="{
                          width:
                            (rankings[0]?.points
                              ? Math.round(
                                  (agent.points / rankings[0].points) * 100
                                )
                              : 0) + '%',
                        }"
                      />
                    </div>
                    <span
                      class="text-xs font-bold text-amber-600 dark:text-amber-400 w-8 text-right"
                      >{{ agent.points }}</span
                    >
                  </div>
                </td>
                <td class="px-4 py-3 text-right">
                  <div v-if="getGoalFor(agent.agent.id)">
                    <div
                      class="text-xs font-medium"
                      :class="
                        goalValuePct(agent.agent.id) >= 100
                          ? 'text-green-600'
                          : 'text-slate-500'
                      "
                    >
                      {{ goalValuePct(agent.agent.id) }}%
                    </div>
                    <div
                      class="w-12 h-1 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden ml-auto mt-0.5"
                    >
                      <div
                        class="h-full rounded-full transition-all"
                        :class="
                          goalValuePct(agent.agent.id) >= 100
                            ? 'bg-green-500'
                            : 'bg-woot-400'
                        "
                        :style="{ width: goalValuePct(agent.agent.id) + '%' }"
                      />
                    </div>
                  </div>
                  <span
                    v-else
                    class="text-[10px] text-slate-300 dark:text-slate-600"
                    >—</span
                  >
                </td>
              </tr>
            </tbody>
          </table>
          <div
            v-if="!rankings.length"
            class="text-center py-10 text-sm text-slate-400"
          >
            Nenhum dado disponível ainda. Crie leads e marque ganhos para
            aparecer aqui.
          </div>
        </div>
      </div>

      <!-- ── METAS INDIVIDUAIS TAB ── -->
      <div v-else-if="activeTab === 'metas'" class="p-5 space-y-3">
        <div class="flex items-center justify-between mb-2">
          <h2 class="text-sm font-semibold text-slate-700 dark:text-slate-200">
            Metas Individuais — {{ monthName }}
          </h2>
          <button
            class="text-xs px-3 py-1.5 rounded-lg bg-woot-500 text-white hover:bg-woot-600 transition-colors flex items-center gap-1.5"
            @click="openSettings"
          >
            <span class="i-lucide-settings size-3.5" /> Configurar Metas
          </button>
        </div>
        <div
          v-if="!rankings.length"
          class="text-center py-12 text-sm text-slate-400"
        >
          Nenhum agente com dados no momento
        </div>
        <div
          v-for="agent in rankings"
          :key="agent.agent.id"
          class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4"
        >
          <div class="flex items-center gap-3 mb-3">
            <img
              v-if="agent.agent.avatar_url"
              :src="agent.agent.avatar_url"
              class="size-9 rounded-full object-cover"
            />
            <div
              v-else
              class="size-9 rounded-full bg-woot-100 dark:bg-woot-900/30 flex items-center justify-center text-sm font-bold text-woot-600 dark:text-woot-400"
            >
              {{ agent.agent.name.charAt(0).toUpperCase() }}
            </div>
            <div class="flex-1">
              <p
                class="text-sm font-semibold text-slate-800 dark:text-slate-100"
              >
                {{ agent.agent.name }}
              </p>
              <div class="flex gap-1 mt-0.5">
                <span
                  v-for="badge in getBadges(agent, rankings)"
                  :key="badge.id"
                  class="text-xs"
                  :title="badge.label"
                  >{{ badge.icon }}</span
                >
              </div>
            </div>
            <div class="text-right text-xs text-slate-400">
              <span class="font-bold text-amber-600 dark:text-amber-400"
                >{{ agent.points }} pts</span
              >
            </div>
          </div>
          <div v-if="getGoalFor(agent.agent.id)" class="space-y-2.5">
            <div>
              <div class="flex justify-between text-[10px] text-slate-500 mb-1">
                <span>Faturamento</span>
                <span class="font-semibold">
                  {{ formatCurrency(agent.stats.value) }}
                  <span class="font-normal text-slate-400">
                    /
                    {{
                      formatCurrency(getGoalFor(agent.agent.id).target_value)
                    }}</span
                  >
                </span>
              </div>
              <div
                class="h-2.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
              >
                <div
                  class="h-full rounded-full transition-all"
                  :class="
                    goalValuePct(agent.agent.id) >= 100
                      ? 'bg-green-500'
                      : goalValuePct(agent.agent.id) >= 70
                        ? 'bg-amber-400'
                        : 'bg-woot-400'
                  "
                  :style="{ width: goalValuePct(agent.agent.id) + '%' }"
                />
              </div>
              <p
                class="text-right text-[10px] mt-0.5"
                :class="
                  goalValuePct(agent.agent.id) >= 100
                    ? 'text-green-600 font-semibold'
                    : 'text-slate-400'
                "
              >
                {{ goalValuePct(agent.agent.id) }}%
                <span v-if="goalValuePct(agent.agent.id) >= 100">✅</span>
              </p>
            </div>
            <div v-if="getGoalFor(agent.agent.id).target_won > 0">
              <div class="flex justify-between text-[10px] text-slate-500 mb-1">
                <span>Fechamentos</span>
                <span class="font-semibold">
                  {{ agent.stats.won }}
                  <span class="font-normal text-slate-400">
                    / {{ getGoalFor(agent.agent.id).target_won }}</span
                  >
                </span>
              </div>
              <div
                class="h-2.5 bg-slate-100 dark:bg-slate-700 rounded-full overflow-hidden"
              >
                <div
                  class="h-full rounded-full transition-all"
                  :class="
                    goalWonPct(agent.agent.id) >= 100
                      ? 'bg-green-500'
                      : goalWonPct(agent.agent.id) >= 70
                        ? 'bg-amber-400'
                        : 'bg-woot-400'
                  "
                  :style="{ width: goalWonPct(agent.agent.id) + '%' }"
                />
              </div>
              <p
                class="text-right text-[10px] mt-0.5"
                :class="
                  goalWonPct(agent.agent.id) >= 100
                    ? 'text-green-600 font-semibold'
                    : 'text-slate-400'
                "
              >
                {{ goalWonPct(agent.agent.id) }}%
                <span v-if="goalWonPct(agent.agent.id) >= 100">✅</span>
              </p>
            </div>
          </div>
          <div v-else class="text-[11px] text-slate-400 italic py-1">
            Nenhuma meta definida —
            <button class="text-woot-500 hover:underline" @click="openSettings">
              configurar
            </button>
          </div>
        </div>

        <!-- Challenges section -->
        <div
          class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 mt-4"
        >
          <h3
            class="text-xs font-semibold text-slate-600 dark:text-slate-300 uppercase tracking-wide mb-3"
          >
            Desafios Ativos
          </h3>
          <div class="space-y-2">
            <div
              v-for="challenge in CHALLENGES"
              :key="challenge.id"
              class="flex items-center gap-3 p-2.5 rounded-lg bg-slate-50 dark:bg-slate-700/50"
            >
              <span class="text-xl shrink-0">{{ challenge.icon }}</span>
              <div class="flex-1">
                <p
                  class="text-xs font-semibold text-slate-700 dark:text-slate-200"
                >
                  {{ challenge.label }}
                </p>
                <p class="text-[10px] text-slate-400">{{ challenge.desc }}</p>
              </div>
              <div class="text-[10px] text-slate-400 shrink-0">
                {{
                  rankings.filter(a => challenge.condition(a, rankings)).length
                }}
                agente(s)
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── WINS TAB ── -->
      <div v-else-if="activeTab === 'wins'" class="p-5 space-y-2">
        <div
          v-if="!recentWins.length"
          class="text-center py-12 text-slate-400 text-sm"
        >
          Nenhuma vitória registrada ainda
        </div>
        <div
          v-for="win in recentWins"
          :key="win.id"
          class="bg-white dark:bg-slate-800 rounded-xl border border-l-4 border-slate-200 dark:border-slate-700 p-4 flex items-center gap-3"
          :style="{ borderLeftColor: win.stage_color || '#22c55e' }"
        >
          <img
            v-if="win.assignee?.avatar_url"
            :src="win.assignee.avatar_url"
            class="size-9 rounded-full shrink-0 object-cover"
          />
          <div
            v-else
            class="size-9 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center text-lg shrink-0"
          >
            🏆
          </div>
          <div class="flex-1 min-w-0">
            <p
              class="text-xs font-semibold text-slate-800 dark:text-slate-100 truncate"
            >
              {{ win.title }}
            </p>
            <div class="flex items-center gap-1.5 mt-0.5">
              <span class="text-[10px] text-slate-400">{{
                win.stage_name
              }}</span>
              <span class="text-slate-300 dark:text-slate-600">·</span>
              <span class="text-[10px] text-slate-400">{{
                win.assignee?.name || '—'
              }}</span>
            </div>
            <p class="text-[10px] text-slate-400 mt-0.5">
              {{ formatDate(win.won_at) }}
            </p>
          </div>
          <div class="text-right shrink-0">
            <p class="text-sm font-bold text-green-600 dark:text-green-400">
              {{ formatCurrency(win.value) }}
            </p>
            <p class="text-[10px] text-green-500">✅ Ganho</p>
          </div>
        </div>
      </div>

      <!-- ── BADGES TAB ── -->
      <div v-else-if="activeTab === 'badges'" class="p-5 space-y-4">
        <div
          class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-5"
        >
          <h3
            class="text-xs font-semibold text-slate-600 dark:text-slate-300 uppercase tracking-wide mb-4"
          >
            Legenda das Badges
          </h3>
          <div class="grid grid-cols-1 gap-3">
            <div
              v-for="b in BADGE_LEGEND"
              :key="b.icon"
              class="flex items-center gap-4 p-3 rounded-lg bg-slate-50 dark:bg-slate-700/50"
            >
              <span class="text-3xl">{{ b.icon }}</span>
              <div>
                <p
                  class="text-sm font-semibold text-slate-700 dark:text-slate-200"
                >
                  {{ b.label }}
                </p>
                <p class="text-xs text-slate-400">{{ b.desc }}</p>
              </div>
            </div>
          </div>
        </div>
        <div
          class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-5"
        >
          <h3
            class="text-xs font-semibold text-slate-600 dark:text-slate-300 uppercase tracking-wide mb-4"
          >
            Como Ganhar Pontos
          </h3>
          <div class="space-y-2.5">
            <div
              v-for="item in [
                { icon: '🎯', label: 'Criar lead no Kanban', pts: '+1 ponto' },
                { icon: '🏆', label: 'Ganhar negócio', pts: '+10 pontos' },
                {
                  icon: '⚡',
                  label: 'Conversão acima de 50%',
                  pts: '+5 pontos bônus',
                },
              ]"
              :key="item.icon"
              class="flex items-center justify-between p-3 rounded-lg bg-slate-50 dark:bg-slate-700/50"
            >
              <div class="flex items-center gap-2.5">
                <span class="text-xl">{{ item.icon }}</span>
                <span class="text-sm text-slate-700 dark:text-slate-200">{{
                  item.label
                }}</span>
              </div>
              <span
                class="text-sm font-bold text-amber-600 dark:text-amber-400"
                >{{ item.pts }}</span
              >
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── SETTINGS PANEL (drawer) ────────────────────────────────────── -->
    <Teleport to="body">
      <div v-if="showSettings" class="fixed inset-0 z-50 flex">
        <!-- Backdrop -->
        <div class="flex-1 bg-black/40" @click="showSettings = false" />

        <!-- Panel -->
        <div
          class="w-[480px] max-w-full bg-white dark:bg-slate-800 h-full flex flex-col shadow-2xl overflow-hidden"
        >
          <!-- Panel header -->
          <div
            class="flex items-center justify-between px-6 py-4 border-b border-slate-200 dark:border-slate-700 shrink-0"
          >
            <div class="flex items-center gap-2.5">
              <span class="text-xl">⚙️</span>
              <div>
                <h2
                  class="text-base font-bold text-slate-800 dark:text-slate-100"
                >
                  Configurações da Gamificação
                </h2>
                <p class="text-xs text-slate-500 dark:text-slate-400">
                  Defina como o ranking e badges funcionam.
                </p>
              </div>
            </div>
            <button
              class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
              @click="showSettings = false"
            >
              <span class="i-lucide-x size-5" />
            </button>
          </div>

          <!-- Panel body -->
          <div class="flex-1 overflow-y-auto px-6 py-4 space-y-6">
            <!-- Modo de Pontuação -->
            <div class="bg-slate-50 dark:bg-slate-700/50 rounded-xl p-4">
              <div class="flex items-center gap-2 mb-3">
                <span class="i-lucide-calculator size-4 text-woot-500" />
                <h3
                  class="text-sm font-semibold text-slate-700 dark:text-slate-200"
                >
                  Modo de Pontuação
                </h3>
              </div>
              <label
                class="flex items-start gap-3 p-3 rounded-lg border border-woot-500 bg-woot-50 dark:bg-woot-900/20 cursor-pointer mb-2"
              >
                <input
                  type="radio"
                  name="scoring_mode"
                  checked
                  class="mt-0.5 accent-woot-500"
                />
                <div>
                  <p
                    class="text-sm font-medium text-slate-700 dark:text-slate-200"
                  >
                    Negociações Ganhas
                  </p>
                  <p class="text-xs text-slate-500 dark:text-slate-400">
                    Conta todas as negociações marcadas como "Ganha".
                  </p>
                </div>
              </label>
              <label
                class="flex items-start gap-3 p-3 rounded-lg border border-slate-200 dark:border-slate-600 cursor-pointer opacity-60"
              >
                <input
                  type="radio"
                  name="scoring_mode"
                  disabled
                  class="mt-0.5"
                />
                <div>
                  <p
                    class="text-sm font-medium text-slate-700 dark:text-slate-200"
                  >
                    Negociações Ganhas + Fatura Paga
                  </p>
                  <p class="text-xs text-slate-500 dark:text-slate-400">
                    Só conta negociações que possuem fatura vinculada com status
                    "Pago".
                  </p>
                </div>
              </label>
            </div>

            <!-- Período do Ranking -->
            <div class="bg-slate-50 dark:bg-slate-700/50 rounded-xl p-4">
              <div class="flex items-center gap-2 mb-3">
                <span class="i-lucide-calendar size-4 text-woot-500" />
                <h3
                  class="text-sm font-semibold text-slate-700 dark:text-slate-200"
                >
                  Período do Ranking
                </h3>
              </div>
              <select
                class="w-full border border-slate-200 dark:border-slate-600 rounded-lg px-3 py-2 text-sm bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-300"
              >
                <option value="monthly" selected>Mensal</option>
                <option value="weekly" disabled>Semanal (em breve)</option>
                <option value="yearly" disabled>Anual (em breve)</option>
              </select>
            </div>

            <!-- Exibição e Recursos -->
            <div class="bg-slate-50 dark:bg-slate-700/50 rounded-xl p-4">
              <div class="flex items-center gap-2 mb-3">
                <span class="i-lucide-eye size-4 text-woot-500" />
                <h3
                  class="text-sm font-semibold text-slate-700 dark:text-slate-200"
                >
                  Exibição e Recursos
                </h3>
              </div>
              <div class="space-y-2.5">
                <label
                  v-for="opt in [
                    { label: 'Exibir valores (R$) no ranking', checked: true },
                    { label: 'Badges automáticos', checked: true },
                    { label: 'Modo TV', checked: true },
                    { label: 'Link público compartilhável', checked: true },
                  ]"
                  :key="opt.label"
                  class="flex items-center justify-between py-1.5 border-b border-slate-200 dark:border-slate-600 last:border-0"
                >
                  <span class="text-sm text-slate-600 dark:text-slate-300">{{
                    opt.label
                  }}</span>
                  <input
                    type="checkbox"
                    :checked="opt.checked"
                    class="accent-woot-500 size-4"
                  />
                </label>
              </div>
            </div>

            <!-- Metas por Usuário -->
            <div class="bg-slate-50 dark:bg-slate-700/50 rounded-xl p-4">
              <div class="flex items-center gap-2 mb-1">
                <span class="i-lucide-users size-4 text-woot-500" />
                <h3
                  class="text-sm font-semibold text-slate-700 dark:text-slate-200"
                >
                  Metas por Usuário
                </h3>
              </div>
              <p class="text-xs text-slate-400 mb-4">
                Defina metas individuais para cada vendedor. Se não definida, a
                meta geral será usada.
              </p>

              <div
                class="space-y-0 border border-slate-200 dark:border-slate-600 rounded-lg overflow-hidden"
              >
                <!-- Header -->
                <div
                  class="grid grid-cols-[1fr_auto_auto] gap-3 px-3 py-2 bg-slate-100 dark:bg-slate-700 border-b border-slate-200 dark:border-slate-600"
                >
                  <span
                    class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                    >Usuário</span
                  >
                  <span
                    class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide w-28 text-center"
                    >Meta Valor (R$)</span
                  >
                  <span
                    class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide w-20 text-center"
                    >Meta Qtd.</span
                  >
                </div>
                <!-- Rows -->
                <div
                  v-for="agent in allAgents"
                  :key="agent.id"
                  class="grid grid-cols-[1fr_auto_auto] gap-3 px-3 py-2.5 border-b border-slate-100 dark:border-slate-700 last:border-0 items-center bg-white dark:bg-slate-800"
                >
                  <div class="flex items-center gap-2 min-w-0">
                    <img
                      v-if="agent.avatar_url"
                      :src="agent.avatar_url"
                      class="size-6 rounded-full object-cover shrink-0"
                    />
                    <div
                      v-else
                      class="size-6 rounded-full bg-slate-200 dark:bg-slate-600 flex items-center justify-center text-xs font-bold text-slate-500 shrink-0"
                    >
                      {{ agent.name.charAt(0).toUpperCase() }}
                    </div>
                    <span
                      class="text-xs text-slate-700 dark:text-slate-200 truncate"
                      >{{ agent.name }}</span
                    >
                  </div>
                  <input
                    v-model="editableGoals[agent.id].targetValue"
                    type="number"
                    placeholder="0"
                    class="w-28 border border-slate-200 dark:border-slate-600 rounded px-2 py-1 text-xs bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-1 focus:ring-woot-300 text-right"
                  />
                  <input
                    v-model="editableGoals[agent.id].targetWon"
                    type="number"
                    placeholder="0"
                    class="w-20 border border-slate-200 dark:border-slate-600 rounded px-2 py-1 text-xs bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-1 focus:ring-woot-300 text-right"
                  />
                </div>
                <div
                  v-if="!allAgents.length"
                  class="px-3 py-4 text-center text-xs text-slate-400"
                >
                  Nenhum agente encontrado
                </div>
              </div>
            </div>
          </div>

          <!-- Panel footer -->
          <div
            class="px-6 py-4 border-t border-slate-200 dark:border-slate-700 shrink-0"
          >
            <button
              class="w-full py-2.5 rounded-xl bg-woot-500 text-white font-semibold hover:bg-woot-600 transition-colors flex items-center justify-center gap-2 disabled:opacity-60"
              :disabled="savingGoals"
              @click="saveAllGoals"
            >
              <span
                v-if="savingGoals"
                class="i-lucide-loader-circle size-4 animate-spin"
              />
              <span v-else class="i-lucide-save size-4" />
              {{ savingGoals ? 'Salvando...' : 'Salvar Configurações' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
