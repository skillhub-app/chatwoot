<script setup>
import { ref, computed, watch, onMounted, reactive } from 'vue';
import { useStore } from 'vuex';
import { gamificationAPI, goalsAPI } from 'dashboard/api/kanban.js';

const store = useStore();
const agents = computed(() => store.getters['agents/getAgents'] || []);

// ── Period ────────────────────────────────────────────────────────────────────
const PERIODS = [
  { id: 'today', label: 'Hoje' },
  { id: 'week', label: 'Semana' },
  { id: 'month', label: 'Mês' },
  { id: 'year', label: 'Ano' },
  { id: 'all', label: 'Total' },
  { id: 'custom', label: 'Custom' },
];
const period = ref('month');
const customFrom = ref('');
const customTo = ref('');

function periodParams() {
  if (period.value === 'all') return {};
  if (period.value === 'custom') {
    return {
      period: 'custom',
      date_from: customFrom.value,
      date_to: customTo.value,
    };
  }
  return { period: period.value };
}

const now = new Date();
const currentYear = now.getFullYear();
const currentMonth = now.getMonth() + 1;

// ── Tabs ─────────────────────────────────────────────────────────────────────
const TABS = [
  { id: 'overview', label: 'Visão Geral', icon: 'i-lucide-layout-dashboard' },
  { id: 'ranking', label: 'Ranking', icon: 'i-lucide-trophy' },
  { id: 'goals', label: 'Metas', icon: 'i-lucide-target' },
  { id: 'badges', label: 'Conquistas', icon: 'i-lucide-award' },
  { id: 'timeline', label: 'Timeline', icon: 'i-lucide-activity' },
];
const activeTab = ref('overview');

// ── Data ─────────────────────────────────────────────────────────────────────
const rankings = ref([]);
const timelineEvents = ref([]);
const goals = ref([]);
const globalGoals = ref({ team_goal_value: 0, team_goal_won: 0 });
const loading = ref(false);

// ── Settings drawer ───────────────────────────────────────────────────────────
const showSettings = ref(false);
const savingGoals = ref(false);
const editGlobal = reactive({ team_goal_value: '', team_goal_won: '' });
const editIndividualMap = ref({});

// ── Load data ─────────────────────────────────────────────────────────────────
async function loadData() {
  loading.value = true;
  try {
    if (!agents.value.length) store.dispatch('agents/get').catch(() => {});
    const pp = periodParams();
    const [rankRes, timeRes, goalRes, globalRes] = await Promise.allSettled([
      gamificationAPI.rankings(pp),
      gamificationAPI.timeline({ ...pp, limit: 50 }),
      goalsAPI.list(currentYear, currentMonth),
      gamificationAPI.globalGoals(),
    ]);
    if (rankRes.status === 'fulfilled')
      rankings.value = rankRes.value.data?.payload || [];
    if (timeRes.status === 'fulfilled')
      timelineEvents.value = timeRes.value.data?.payload || [];
    if (goalRes.status === 'fulfilled')
      goals.value = goalRes.value.data?.payload || [];
    if (globalRes.status === 'fulfilled')
      globalGoals.value = globalRes.value.data?.payload || {};
  } finally {
    loading.value = false;
  }
}

watch(period, () => loadData());

onMounted(async () => {
  await loadData();
});

// ── Computed ──────────────────────────────────────────────────────────────────
const goalsMap = computed(() => {
  const m = {};
  goals.value.forEach(g => {
    m[g.assignee_id] = g;
  });
  return m;
});

function openSettings() {
  editGlobal.team_goal_value = globalGoals.value.team_goal_value || '';
  editGlobal.team_goal_won = globalGoals.value.team_goal_won || '';
  const map = {};
  agents.value.forEach(a => {
    const g = goalsMap.value[a.id];
    map[a.id] = {
      target_value: g?.target_value || '',
      target_won: g?.target_won || '',
    };
  });
  editIndividualMap.value = map;
  showSettings.value = true;
}

async function saveSettings() {
  savingGoals.value = true;
  try {
    await gamificationAPI.updateGlobalGoals({
      team_goal_value: parseFloat(editGlobal.team_goal_value) || 0,
      team_goal_won: parseInt(editGlobal.team_goal_won, 10) || 0,
    });
    const upserts = agents.value
      .filter(a => {
        const e = editIndividualMap.value[a.id];
        return (
          e &&
          (parseFloat(e.target_value) > 0 || parseInt(e.target_won, 10) > 0)
        );
      })
      .map(a => {
        const e = editIndividualMap.value[a.id];
        return goalsAPI.upsert({
          assignee_id: a.id,
          year: currentYear,
          month: currentMonth,
          target_value: parseFloat(e.target_value) || 0,
          target_won: parseInt(e.target_won, 10) || 0,
        });
      });
    await Promise.all(upserts);
    showSettings.value = false;
    await loadData();
  } finally {
    savingGoals.value = false;
  }
}

// Podium display order: [silver, gold, bronze]
const podiumItems = computed(() => {
  const top = rankings.value.slice(0, 3);
  if (top.length === 0) return [];
  if (top.length === 1) return [null, top[0], null];
  if (top.length === 2) return [top[1], top[0], null];
  return [top[1], top[0], top[2]];
});

// Map podium display index → actual rank (0=gold, 1=silver, 2=bronze)
const PODIUM_RANKS = [1, 0, 2];

const teamTotalWon = computed(() =>
  rankings.value.reduce((s, r) => s + r.stats.won, 0)
);
const teamTotalValue = computed(() =>
  rankings.value.reduce((s, r) => s + r.stats.value, 0)
);
const teamGoalValuePct = computed(() => {
  if (!globalGoals.value.team_goal_value) return null;
  return Math.min(
    100,
    (teamTotalValue.value / globalGoals.value.team_goal_value) * 100
  ).toFixed(1);
});
const teamGoalWonPct = computed(() => {
  if (!globalGoals.value.team_goal_won) return null;
  return Math.min(
    100,
    (teamTotalWon.value / globalGoals.value.team_goal_won) * 100
  ).toFixed(1);
});

// ── Goal helpers ─────────────────────────────────────────────────────────────
function goalPct(agentId) {
  const g = goalsMap.value[agentId];
  const r = rankings.value.find(x => x.agent.id === agentId);
  if (!g || !r || !g.target_value) return 0;
  return Math.min(100, (r.stats.value / g.target_value) * 100);
}

// ── Badges ───────────────────────────────────────────────────────────────────
const BADGE_DEFS = [
  {
    id: 'primeira_venda',
    name: 'Primeira Venda',
    icon: '🎯',
    desc: 'Fechou ao menos 1 negócio',
    check: r => r.stats.won >= 1,
    color:
      'bg-emerald-50 border-emerald-200 text-emerald-700 dark:bg-emerald-900/20 dark:border-emerald-700',
  },
  {
    id: 'cinco_vendas',
    name: 'Cinco em Campo',
    icon: '🔥',
    desc: '5 ou mais negócios fechados',
    check: r => r.stats.won >= 5,
    color:
      'bg-orange-50 border-orange-200 text-orange-700 dark:bg-orange-900/20 dark:border-orange-700',
  },
  {
    id: 'dez_vendas',
    name: 'Máquina de Vendas',
    icon: '🏭',
    desc: '10 ou mais negócios fechados',
    check: r => r.stats.won >= 10,
    color:
      'bg-red-50 border-red-200 text-red-700 dark:bg-red-900/20 dark:border-red-700',
  },
  {
    id: 'conversor',
    name: 'Conversor',
    icon: '⚡',
    desc: 'Taxa de conversão acima de 70%',
    check: r => r.stats.conversion_rate >= 70,
    color:
      'bg-yellow-50 border-yellow-200 text-yellow-700 dark:bg-yellow-900/20 dark:border-yellow-700',
  },
  {
    id: 'grande_negocio',
    name: 'Grande Negócio',
    icon: '💎',
    desc: 'Fechou deal acima de R$ 10.000',
    check: r => r.stats.max_deal_value >= 10000,
    color:
      'bg-blue-50 border-blue-200 text-blue-700 dark:bg-blue-900/20 dark:border-blue-700',
  },
  {
    id: 'meta_batida',
    name: 'Meta Batida',
    icon: '🏆',
    desc: 'Atingiu 100% da meta individual',
    check: r => goalPct(r.agent.id) >= 100,
    color:
      'bg-woot-50 border-woot-200 text-woot-700 dark:bg-woot-900/20 dark:border-woot-700',
  },
  {
    id: 'lider',
    name: 'Líder do Período',
    icon: '👑',
    desc: 'Maior pontuação do período',
    check: (r, idx) => idx === 0,
    color:
      'bg-amber-50 border-amber-200 text-amber-700 dark:bg-amber-900/20 dark:border-amber-700',
  },
  {
    id: 'faturamento_50k',
    name: 'R$ 50K+ Club',
    icon: '💰',
    desc: 'R$ 50.000 ou mais em faturamento',
    check: r => r.stats.value >= 50000,
    color:
      'bg-green-50 border-green-200 text-green-700 dark:bg-green-900/20 dark:border-green-700',
  },
];

const agentBadges = computed(() => {
  const map = {};
  rankings.value.forEach((r, idx) => {
    map[r.agent.id] = BADGE_DEFS.filter(b => b.check(r, idx));
  });
  return map;
});

function goalWonPct(agentId) {
  const g = goalsMap.value[agentId];
  const r = rankings.value.find(x => x.agent.id === agentId);
  if (!g || !r || !g.target_won) return 0;
  return Math.min(100, (r.stats.won / g.target_won) * 100);
}

function agentWon(agentId) {
  return rankings.value.find(r => r.agent.id === agentId)?.stats.won || 0;
}

function agentValue(agentId) {
  return rankings.value.find(r => r.agent.id === agentId)?.stats.value || 0;
}

// ── Formatters ────────────────────────────────────────────────────────────────
function fBRL(val) {
  if (!val) return 'R$ 0';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(val);
}

function fTs(ts) {
  if (!ts) return '—';
  return new Date(ts * 1000).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function fRelative(ts) {
  if (!ts) return '';
  const diff = Math.floor((Date.now() - ts * 1000) / 1000);
  if (diff < 60) return `${diff}s atrás`;
  if (diff < 3600) return `${Math.floor(diff / 60)}min atrás`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h atrás`;
  return `${Math.floor(diff / 86400)}d atrás`;
}

function initials(name) {
  if (!name) return '?';
  return name
    .split(' ')
    .slice(0, 2)
    .map(w => w[0])
    .join('')
    .toUpperCase();
}

const MEDAL = [
  {
    ring: 'ring-amber-400',
    bg: 'bg-gradient-to-b from-amber-300 to-amber-400',
    emoji: '🥇',
    bar: 'from-amber-400 to-amber-300',
    h: 'h-24',
  },
  {
    ring: 'ring-slate-400',
    bg: 'bg-gradient-to-b from-slate-300 to-slate-400',
    emoji: '🥈',
    bar: 'from-slate-400 to-slate-300',
    h: 'h-16',
  },
  {
    ring: 'ring-amber-700',
    bg: 'bg-gradient-to-b from-amber-600 to-amber-700',
    emoji: '🥉',
    bar: 'from-amber-700 to-amber-600',
    h: 'h-12',
  },
];
</script>

<template>
  <div class="flex flex-col h-full bg-white dark:bg-slate-900 overflow-hidden">
    <!-- ── Top bar ───────────────────────────────────────────────────────────── -->
    <div
      class="flex items-center gap-3 px-5 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0 flex-wrap"
    >
      <div class="flex items-center gap-2">
        <span class="i-lucide-trophy size-5 text-amber-500" />
        <h1 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          Gamificação Comercial
        </h1>
      </div>

      <!-- Period selector -->
      <div
        class="flex items-center rounded-lg border border-slate-200 dark:border-slate-700 overflow-hidden"
      >
        <button
          v-for="p in PERIODS"
          :key="p.id"
          class="text-xs px-3 py-1.5 font-medium transition-colors border-r border-slate-200 dark:border-slate-700 last:border-r-0"
          :class="
            period === p.id
              ? 'bg-woot-500 text-white'
              : 'text-slate-500 dark:text-slate-400 hover:bg-slate-50 dark:hover:bg-slate-800'
          "
          @click="period = p.id"
        >
          {{ p.label }}
        </button>
      </div>

      <!-- Custom range -->
      <div v-if="period === 'custom'" class="flex items-center gap-2">
        <input
          v-model="customFrom"
          type="date"
          class="text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none"
          @change="loadData"
        />
        <span class="text-xs text-slate-400">até</span>
        <input
          v-model="customTo"
          type="date"
          class="text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none"
          @change="loadData"
        />
      </div>

      <div class="ml-auto flex items-center gap-2">
        <span
          v-if="loading"
          class="i-lucide-loader-circle size-4 animate-spin text-woot-500"
        />
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700 font-medium transition-colors"
          @click="openSettings"
        >
          <span class="i-lucide-settings size-3.5" />
          Configurações
        </button>
      </div>
    </div>

    <!-- ── Tab bar ───────────────────────────────────────────────────────────── -->
    <div
      class="flex items-center border-b border-slate-200 dark:border-slate-700 shrink-0 overflow-x-auto bg-white dark:bg-slate-900"
    >
      <button
        v-for="tab in TABS"
        :key="tab.id"
        class="flex items-center gap-1.5 px-5 py-3 text-xs font-medium whitespace-nowrap border-b-2 transition-colors"
        :class="
          activeTab === tab.id
            ? 'border-woot-500 text-woot-600 dark:text-woot-400'
            : 'border-transparent text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200'
        "
        @click="activeTab = tab.id"
      >
        <span class="size-3.5" :class="[tab.icon]" />
        {{ tab.label }}
      </button>
    </div>

    <!-- ── Tab content ───────────────────────────────────────────────────────── -->
    <div class="flex-1 overflow-y-auto">
      <!-- ════ VISÃO GERAL ════════════════════════════════════════════════════ -->
      <div
        v-if="activeTab === 'overview'"
        class="p-5 space-y-6 max-w-5xl mx-auto"
      >
        <!-- Team KPI cards -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div
            class="rounded-xl p-4 border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800"
          >
            <p
              class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1"
            >
              Vendas no Período
            </p>
            <p class="text-3xl font-bold text-slate-800 dark:text-slate-100">
              {{ teamTotalWon }}
            </p>
            <div v-if="teamGoalWonPct" class="mt-2">
              <div class="flex justify-between text-[10px] text-slate-400 mb-1">
                <span>Meta: {{ globalGoals.team_goal_won }}</span>
                <span class="font-semibold text-woot-600"
                  >{{ teamGoalWonPct }}%</span
                >
              </div>
              <div class="h-1.5 rounded-full bg-slate-100 dark:bg-slate-700">
                <div
                  class="h-full rounded-full bg-woot-500 transition-all"
                  :style="{ width: teamGoalWonPct + '%' }"
                />
              </div>
            </div>
          </div>

          <div
            class="rounded-xl p-4 border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800"
          >
            <p
              class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1"
            >
              Faturamento
            </p>
            <p class="text-2xl font-bold text-green-600 dark:text-green-400">
              {{ fBRL(teamTotalValue) }}
            </p>
            <div v-if="teamGoalValuePct" class="mt-2">
              <div class="flex justify-between text-[10px] text-slate-400 mb-1">
                <span>Meta: {{ fBRL(globalGoals.team_goal_value) }}</span>
                <span class="font-semibold text-green-600"
                  >{{ teamGoalValuePct }}%</span
                >
              </div>
              <div class="h-1.5 rounded-full bg-slate-100 dark:bg-slate-700">
                <div
                  class="h-full rounded-full bg-green-500 transition-all"
                  :style="{ width: teamGoalValuePct + '%' }"
                />
              </div>
            </div>
          </div>

          <div
            class="rounded-xl p-4 border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800"
          >
            <p
              class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1"
            >
              Ticket Médio
            </p>
            <p class="text-2xl font-bold text-woot-600 dark:text-woot-400">
              {{
                teamTotalWon > 0 ? fBRL(teamTotalValue / teamTotalWon) : 'R$ 0'
              }}
            </p>
          </div>

          <div
            class="rounded-xl p-4 border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800"
          >
            <p
              class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1"
            >
              Ativos no Ranking
            </p>
            <p class="text-3xl font-bold text-slate-800 dark:text-slate-100">
              {{ rankings.length }}
            </p>
          </div>
        </div>

        <!-- Podium -->
        <div v-if="rankings.length > 0">
          <h2
            class="text-xs font-semibold text-slate-400 uppercase tracking-wide mb-5 flex items-center gap-2"
          >
            <span class="i-lucide-trophy size-3.5 text-amber-500" />
            Top 3 do Período
          </h2>

          <div class="flex items-end justify-center gap-6 pb-2">
            <div
              v-for="(entry, dispIdx) in podiumItems"
              :key="dispIdx"
              class="flex flex-col items-center"
            >
              <template v-if="entry">
                <!-- Crown for 1st (display center = gold) -->
                <span
                  v-if="PODIUM_RANKS[dispIdx] === 0"
                  class="text-3xl mb-1 animate-bounce"
                  >👑</span
                >

                <!-- Avatar -->
                <div
                  class="relative mb-2 ring-4 rounded-full shadow-lg"
                  :class="[
                    MEDAL[PODIUM_RANKS[dispIdx]].ring,
                    PODIUM_RANKS[dispIdx] === 0 ? 'size-20' : 'size-14',
                  ]"
                >
                  <img
                    v-if="entry.agent.avatar_url"
                    :src="entry.agent.avatar_url"
                    :alt="entry.agent.name"
                    class="rounded-full object-cover w-full h-full"
                  />
                  <div
                    v-else
                    class="rounded-full w-full h-full flex items-center justify-center text-white font-bold"
                    :class="[
                      MEDAL[PODIUM_RANKS[dispIdx]].bg,
                      PODIUM_RANKS[dispIdx] === 0 ? 'text-2xl' : 'text-base',
                    ]"
                  >
                    {{ initials(entry.agent.name) }}
                  </div>
                  <span class="absolute -bottom-1.5 -right-1 text-xl">
                    {{ MEDAL[PODIUM_RANKS[dispIdx]].emoji }}
                  </span>
                </div>

                <!-- Name -->
                <p
                  class="text-sm font-bold text-slate-800 dark:text-slate-100 truncate text-center max-w-28"
                >
                  {{ entry.agent.name.split(' ')[0] }}
                </p>
                <p
                  class="text-xs font-semibold text-green-600 dark:text-green-400 mt-0.5"
                >
                  {{ fBRL(entry.stats.value) }}
                </p>
                <p class="text-[10px] text-slate-400">
                  {{ entry.stats.won }} venda{{
                    entry.stats.won !== 1 ? 's' : ''
                  }}
                </p>

                <!-- Badges -->
                <div
                  v-if="agentBadges[entry.agent.id]?.length"
                  class="flex gap-0.5 mt-1.5 flex-wrap justify-center max-w-28"
                >
                  <span
                    v-for="b in agentBadges[entry.agent.id].slice(0, 4)"
                    :key="b.id"
                    :title="b.name"
                    class="text-sm"
                    >{{ b.icon }}</span
                  >
                </div>

                <!-- Podium bar -->
                <div
                  class="w-28 rounded-t-xl mt-3 flex items-center justify-center bg-gradient-to-t"
                  :class="[
                    MEDAL[PODIUM_RANKS[dispIdx]].bar,
                    MEDAL[PODIUM_RANKS[dispIdx]].h,
                  ]"
                >
                  <span class="text-white font-bold text-sm"
                    >{{ entry.points }}pt</span
                  >
                </div>
              </template>
              <template v-else>
                <div
                  class="w-28 rounded-t-xl mt-3 bg-slate-100 dark:bg-slate-800"
                  :class="PODIUM_RANKS[dispIdx] === 1 ? 'h-16' : 'h-12'"
                />
              </template>
            </div>
          </div>
        </div>

        <!-- Empty -->
        <div
          v-else-if="!loading"
          class="flex flex-col items-center justify-center py-16 text-center"
        >
          <span
            class="i-lucide-bar-chart-3 size-12 text-slate-300 dark:text-slate-600 mb-3"
          />
          <p class="text-sm font-semibold text-slate-600 dark:text-slate-300">
            Nenhum dado para o período
          </p>
          <p class="text-xs text-slate-400 mt-1">
            Marque negócios como Ganho no Kanban para ver o ranking aqui.
          </p>
        </div>

        <!-- Recent timeline mini -->
        <div v-if="timelineEvents.length">
          <h2
            class="text-xs font-semibold text-slate-400 uppercase tracking-wide mb-3 flex items-center gap-2"
          >
            <span class="i-lucide-activity size-3.5" />
            Últimas Conquistas
          </h2>
          <div class="space-y-2">
            <div
              v-for="ev in timelineEvents.slice(0, 8)"
              :key="ev.id"
              class="flex items-center gap-3 px-3 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-800 border border-slate-100 dark:border-slate-700"
            >
              <div v-if="ev.agent" class="shrink-0">
                <img
                  v-if="ev.agent.avatar_url"
                  :src="ev.agent.avatar_url"
                  class="size-7 rounded-full object-cover"
                />
                <div
                  v-else
                  class="size-7 rounded-full bg-woot-100 dark:bg-woot-800 flex items-center justify-center text-[10px] font-bold text-woot-600"
                >
                  {{ initials(ev.agent.name) }}
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-xs text-slate-700 dark:text-slate-200 truncate">
                  <span class="font-semibold">{{
                    ev.agent?.name || 'Sistema'
                  }}</span>
                  {{
                    ev.action_type === 'won'
                      ? ' fechou'
                      : ev.action_type === 'lost'
                        ? ' perdeu'
                        : ' reabriu'
                  }}
                  <span class="font-medium"> "{{ ev.item.title }}"</span>
                  <span
                    v-if="ev.item.value"
                    class="text-green-600 font-semibold"
                  >
                    · {{ fBRL(ev.item.value) }}</span
                  >
                </p>
              </div>
              <span class="text-[10px] text-slate-400 shrink-0">{{
                fRelative(ev.created_at)
              }}</span>
              <span class="shrink-0 text-base">{{
                ev.action_type === 'won'
                  ? '🏆'
                  : ev.action_type === 'lost'
                    ? '❌'
                    : '🔄'
              }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- ════ RANKING ════════════════════════════════════════════════════════ -->
      <div v-else-if="activeTab === 'ranking'" class="p-5 max-w-5xl mx-auto">
        <div
          v-if="rankings.length"
          class="rounded-xl border border-slate-200 dark:border-slate-700 overflow-hidden"
        >
          <table class="w-full text-sm">
            <thead>
              <tr
                class="bg-slate-50 dark:bg-slate-800 border-b border-slate-200 dark:border-slate-700"
              >
                <th
                  class="text-left px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide w-10"
                >
                  #
                </th>
                <th
                  class="text-left px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Vendedor
                </th>
                <th
                  class="text-right px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Vendas
                </th>
                <th
                  class="text-right px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Faturado
                </th>
                <th
                  class="text-right px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Conv%
                </th>
                <th
                  class="text-right px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Meta%
                </th>
                <th
                  class="text-right px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Pts
                </th>
                <th
                  class="text-left px-4 py-3 text-[10px] font-semibold text-slate-400 uppercase tracking-wide"
                >
                  Badges
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(entry, idx) in rankings"
                :key="entry.agent.id"
                class="border-b border-slate-100 dark:border-slate-800 hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors"
                :class="idx === 0 ? 'bg-amber-50/40 dark:bg-amber-900/10' : ''"
              >
                <td class="px-4 py-3 text-center">
                  <span v-if="idx < 3" class="text-base">{{
                    ['🥇', '🥈', '🥉'][idx]
                  }}</span>
                  <span v-else class="text-xs font-bold text-slate-400">{{
                    idx + 1
                  }}</span>
                </td>
                <td class="px-4 py-3">
                  <div class="flex items-center gap-2.5">
                    <img
                      v-if="entry.agent.avatar_url"
                      :src="entry.agent.avatar_url"
                      class="size-7 rounded-full object-cover shrink-0"
                    />
                    <div
                      v-else
                      class="size-7 rounded-full bg-woot-100 dark:bg-woot-800 flex items-center justify-center text-[10px] font-bold text-woot-600 shrink-0"
                    >
                      {{ initials(entry.agent.name) }}
                    </div>
                    <div>
                      <p
                        class="text-xs font-medium text-slate-800 dark:text-slate-100"
                      >
                        {{ entry.agent.name }}
                      </p>
                      <p class="text-[10px] text-slate-400">
                        {{ entry.stats.open }} em aberto
                      </p>
                    </div>
                  </div>
                </td>
                <td class="px-4 py-3 text-right">
                  <span
                    class="text-sm font-bold text-slate-800 dark:text-slate-100"
                    >{{ entry.stats.won }}</span
                  >
                  <span class="text-[10px] text-slate-400"
                    >/{{ entry.stats.total }}</span
                  >
                </td>
                <td
                  class="px-4 py-3 text-right text-sm font-semibold text-green-600 dark:text-green-400"
                >
                  {{ fBRL(entry.stats.value) }}
                </td>
                <td class="px-4 py-3 text-right">
                  <span
                    class="text-xs font-medium"
                    :class="
                      entry.stats.conversion_rate >= 70
                        ? 'text-green-600'
                        : entry.stats.conversion_rate >= 40
                          ? 'text-amber-600'
                          : 'text-red-500'
                    "
                    >{{ entry.stats.conversion_rate }}%</span
                  >
                </td>
                <td class="px-4 py-3 text-right">
                  <div
                    v-if="goalsMap[entry.agent.id]"
                    class="flex flex-col items-end"
                  >
                    <span
                      class="text-xs font-semibold"
                      :class="
                        goalPct(entry.agent.id) >= 100
                          ? 'text-green-600'
                          : 'text-slate-500'
                      "
                    >
                      {{ goalPct(entry.agent.id).toFixed(0) }}%
                    </span>
                    <div
                      class="w-16 h-1 rounded-full bg-slate-200 dark:bg-slate-700 mt-1"
                    >
                      <div
                        class="h-full rounded-full transition-all"
                        :class="
                          goalPct(entry.agent.id) >= 100
                            ? 'bg-green-500'
                            : 'bg-woot-500'
                        "
                        :style="{ width: goalPct(entry.agent.id) + '%' }"
                      />
                    </div>
                  </div>
                  <span v-else class="text-[10px] text-slate-300">—</span>
                </td>
                <td class="px-4 py-3 text-right">
                  <span
                    class="text-sm font-bold"
                    :class="
                      idx === 0
                        ? 'text-amber-500'
                        : 'text-slate-700 dark:text-slate-300'
                    "
                    >{{ entry.points }}</span
                  >
                </td>
                <td class="px-4 py-3">
                  <div class="flex items-center gap-0.5 flex-wrap max-w-20">
                    <span
                      v-for="b in (agentBadges[entry.agent.id] || []).slice(
                        0,
                        5
                      )"
                      :key="b.id"
                      :title="b.name + ': ' + b.desc"
                      class="text-sm cursor-help"
                      >{{ b.icon }}</span
                    >
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div
          v-else-if="!loading"
          class="flex flex-col items-center py-16 text-center"
        >
          <span
            class="i-lucide-users size-10 text-slate-300 dark:text-slate-600 mb-3"
          />
          <p class="text-sm text-slate-500">
            Nenhum vendedor com dados para este período.
          </p>
        </div>
      </div>

      <!-- ════ METAS ══════════════════════════════════════════════════════════ -->
      <div
        v-else-if="activeTab === 'goals'"
        class="p-5 space-y-5 max-w-4xl mx-auto"
      >
        <!-- Team goal banner -->
        <div
          v-if="globalGoals.team_goal_value || globalGoals.team_goal_won"
          class="rounded-xl border border-woot-200 dark:border-woot-700 bg-woot-50 dark:bg-woot-900/20 p-5"
        >
          <div class="flex items-center gap-2 mb-4">
            <span class="i-lucide-target size-4 text-woot-500" />
            <h3
              class="text-sm font-semibold text-slate-800 dark:text-slate-100"
            >
              Meta do Time
            </h3>
          </div>
          <div class="grid grid-cols-2 gap-5">
            <div v-if="globalGoals.team_goal_value">
              <div class="flex justify-between text-xs mb-1.5">
                <span class="text-slate-500">Faturamento</span>
                <span class="font-bold text-slate-700 dark:text-slate-200"
                  >{{ fBRL(teamTotalValue) }} /
                  {{ fBRL(globalGoals.team_goal_value) }}</span
                >
              </div>
              <div
                class="h-3 rounded-full bg-slate-200 dark:bg-slate-700 overflow-hidden"
              >
                <div
                  class="h-full rounded-full transition-all"
                  :class="
                    parseFloat(teamGoalValuePct) >= 100
                      ? 'bg-green-500'
                      : 'bg-woot-500'
                  "
                  :style="{ width: (teamGoalValuePct || 0) + '%' }"
                />
              </div>
              <p
                class="text-[10px] font-semibold mt-1"
                :class="
                  parseFloat(teamGoalValuePct) >= 100
                    ? 'text-green-600'
                    : 'text-woot-600'
                "
              >
                {{ teamGoalValuePct || 0 }}%
                {{
                  parseFloat(teamGoalValuePct) >= 100 ? '🎉 Meta atingida!' : ''
                }}
              </p>
            </div>
            <div v-if="globalGoals.team_goal_won">
              <div class="flex justify-between text-xs mb-1.5">
                <span class="text-slate-500">Vendas</span>
                <span class="font-bold text-slate-700 dark:text-slate-200"
                  >{{ teamTotalWon }} / {{ globalGoals.team_goal_won }}</span
                >
              </div>
              <div
                class="h-3 rounded-full bg-slate-200 dark:bg-slate-700 overflow-hidden"
              >
                <div
                  class="h-full rounded-full transition-all"
                  :class="
                    parseFloat(teamGoalWonPct) >= 100
                      ? 'bg-green-500'
                      : 'bg-amber-500'
                  "
                  :style="{ width: (teamGoalWonPct || 0) + '%' }"
                />
              </div>
              <p
                class="text-[10px] font-semibold mt-1"
                :class="
                  parseFloat(teamGoalWonPct) >= 100
                    ? 'text-green-600'
                    : 'text-amber-600'
                "
              >
                {{ teamGoalWonPct || 0 }}%
              </p>
            </div>
          </div>
        </div>

        <!-- Individual cards -->
        <div>
          <h3
            class="text-xs font-semibold text-slate-400 uppercase tracking-wide mb-3"
          >
            Metas Individuais —
            {{
              new Date().toLocaleString('pt-BR', {
                month: 'long',
                year: 'numeric',
              })
            }}
          </h3>
          <div
            v-if="agents.length"
            class="grid grid-cols-1 md:grid-cols-2 gap-3"
          >
            <div
              v-for="agent in agents"
              :key="agent.id"
              class="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-4"
            >
              <div class="flex items-center gap-2.5 mb-3">
                <img
                  v-if="agent.avatar_url"
                  :src="agent.avatar_url"
                  class="size-9 rounded-full object-cover shrink-0"
                />
                <div
                  v-else
                  class="size-9 rounded-full bg-woot-100 dark:bg-woot-800 flex items-center justify-center text-xs font-bold text-woot-600 shrink-0"
                >
                  {{ initials(agent.name) }}
                </div>
                <div class="flex-1 min-w-0">
                  <p
                    class="text-sm font-semibold text-slate-800 dark:text-slate-100"
                  >
                    {{ agent.name }}
                  </p>
                  <div class="flex items-center gap-1">
                    <span
                      v-for="b in (agentBadges[agent.id] || []).slice(0, 3)"
                      :key="b.id"
                      class="text-xs"
                      >{{ b.icon }}</span
                    >
                  </div>
                </div>
                <span
                  v-if="goalsMap[agent.id]"
                  class="shrink-0 text-[10px] font-semibold px-2 py-0.5 rounded-full"
                  :class="
                    goalPct(agent.id) >= 100
                      ? 'bg-green-100 text-green-700'
                      : goalPct(agent.id) >= 50
                        ? 'bg-amber-100 text-amber-700'
                        : 'bg-red-50 text-red-600'
                  "
                >
                  {{
                    goalPct(agent.id) >= 100
                      ? '✓ Meta atingida'
                      : goalPct(agent.id) >= 50
                        ? 'Em andamento'
                        : 'Abaixo da meta'
                  }}
                </span>
                <span v-else class="text-[10px] text-slate-400 shrink-0"
                  >Sem meta</span
                >
              </div>

              <div v-if="goalsMap[agent.id]?.target_value" class="mb-2.5">
                <div
                  class="flex justify-between text-[10px] text-slate-500 mb-1"
                >
                  <span>Faturamento</span>
                  <span class="font-semibold"
                    >{{ fBRL(agentValue(agent.id)) }} /
                    {{ fBRL(goalsMap[agent.id].target_value) }}</span
                  >
                </div>
                <div
                  class="h-2 rounded-full bg-slate-100 dark:bg-slate-700 overflow-hidden"
                >
                  <div
                    class="h-full rounded-full transition-all"
                    :class="
                      goalPct(agent.id) >= 100 ? 'bg-green-500' : 'bg-woot-500'
                    "
                    :style="{ width: goalPct(agent.id) + '%' }"
                  />
                </div>
              </div>

              <div v-if="goalsMap[agent.id]?.target_won">
                <div
                  class="flex justify-between text-[10px] text-slate-500 mb-1"
                >
                  <span>Vendas</span>
                  <span class="font-semibold"
                    >{{ agentWon(agent.id) }} /
                    {{ goalsMap[agent.id].target_won }}</span
                  >
                </div>
                <div
                  class="h-2 rounded-full bg-slate-100 dark:bg-slate-700 overflow-hidden"
                >
                  <div
                    class="h-full rounded-full bg-amber-500 transition-all"
                    :style="{ width: goalWonPct(agent.id) + '%' }"
                  />
                </div>
              </div>

              <div
                v-if="!goalsMap[agent.id]"
                class="text-xs text-slate-400 text-center py-1"
              >
                Configure metas em Configurações
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ════ CONQUISTAS ═════════════════════════════════════════════════════ -->
      <div v-else-if="activeTab === 'badges'" class="p-5 max-w-4xl mx-auto">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div
            v-for="badge in BADGE_DEFS"
            :key="badge.id"
            class="rounded-xl border p-4"
            :class="badge.color"
          >
            <div class="flex items-start gap-3">
              <span class="text-3xl shrink-0">{{ badge.icon }}</span>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-bold mb-0.5">{{ badge.name }}</p>
                <p class="text-xs opacity-70 mb-3">{{ badge.desc }}</p>
                <div v-if="rankings.some((r, i) => badge.check(r, i))">
                  <p
                    class="text-[10px] font-semibold opacity-60 mb-1.5 uppercase tracking-wide"
                  >
                    Conquistado por:
                  </p>
                  <div class="flex flex-wrap gap-1.5">
                    <div
                      v-for="entry in rankings.filter((r, i) =>
                        badge.check(r, i)
                      )"
                      :key="entry.agent.id"
                      class="flex items-center gap-1.5 bg-white/50 dark:bg-black/20 rounded-full px-2 py-0.5"
                    >
                      <img
                        v-if="entry.agent.avatar_url"
                        :src="entry.agent.avatar_url"
                        class="size-4 rounded-full object-cover"
                      />
                      <span
                        v-else
                        class="size-4 rounded-full bg-white/70 flex items-center justify-center text-[8px] font-bold"
                        >{{ initials(entry.agent.name) }}</span
                      >
                      <span class="text-[10px] font-semibold">{{
                        entry.agent.name.split(' ')[0]
                      }}</span>
                    </div>
                  </div>
                </div>
                <p v-else class="text-[10px] opacity-50 italic">
                  Ainda não conquistado neste período
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ════ TIMELINE ═══════════════════════════════════════════════════════ -->
      <div v-else-if="activeTab === 'timeline'" class="p-5 max-w-3xl mx-auto">
        <div v-if="timelineEvents.length" class="space-y-2">
          <div
            v-for="ev in timelineEvents"
            :key="ev.id"
            class="flex items-start gap-3 px-4 py-3 rounded-xl border"
            :class="
              ev.action_type === 'won'
                ? 'bg-green-50 dark:bg-green-900/10 border-green-100 dark:border-green-800'
                : ev.action_type === 'lost'
                  ? 'bg-red-50 dark:bg-red-900/10 border-red-100 dark:border-red-800'
                  : 'bg-blue-50 dark:bg-blue-900/10 border-blue-100 dark:border-blue-800'
            "
          >
            <div
              class="shrink-0 size-9 rounded-full flex items-center justify-center text-xl mt-0.5"
              :class="
                ev.action_type === 'won'
                  ? 'bg-green-100'
                  : ev.action_type === 'lost'
                    ? 'bg-red-100'
                    : 'bg-blue-100'
              "
            >
              {{
                ev.action_type === 'won'
                  ? '🏆'
                  : ev.action_type === 'lost'
                    ? '❌'
                    : '🔄'
              }}
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-xs text-slate-700 dark:text-slate-200">
                <span class="font-semibold">{{
                  ev.agent?.name || 'Sistema'
                }}</span>
                {{
                  ev.action_type === 'won'
                    ? ' marcou como GANHO:'
                    : ev.action_type === 'lost'
                      ? ' marcou como PERDIDO:'
                      : ' REABRIU:'
                }}
                <span class="font-medium ml-1">{{ ev.item.title }}</span>
              </p>
              <div class="flex items-center gap-3 mt-0.5">
                <span
                  v-if="ev.item.value"
                  class="text-xs font-bold text-green-600 dark:text-green-400"
                  >{{ fBRL(ev.item.value) }}</span
                >
                <span
                  v-if="ev.item.pipeline_name"
                  class="text-[10px] text-slate-400"
                  >{{ ev.item.pipeline_name }}</span
                >
              </div>
            </div>
            <div class="shrink-0 flex flex-col items-end gap-1">
              <img
                v-if="ev.agent?.avatar_url"
                :src="ev.agent.avatar_url"
                class="size-6 rounded-full object-cover"
              />
              <div
                v-else-if="ev.agent"
                class="size-6 rounded-full bg-slate-200 flex items-center justify-center text-[9px] font-bold text-slate-500"
              >
                {{ initials(ev.agent.name) }}
              </div>
              <span class="text-[10px] text-slate-400">{{
                fTs(ev.created_at)
              }}</span>
            </div>
          </div>
        </div>
        <div
          v-else-if="!loading"
          class="flex flex-col items-center py-16 text-center"
        >
          <span
            class="i-lucide-clock size-10 text-slate-300 dark:text-slate-600 mb-3"
          />
          <p class="text-sm text-slate-500">
            Nenhuma atividade encontrada para este período.
          </p>
        </div>
      </div>
    </div>

    <!-- ── Settings drawer ───────────────────────────────────────────────────── -->
    <div
      v-if="showSettings"
      class="fixed inset-0 z-50 flex justify-end bg-black/20"
      @click.self="showSettings = false"
    >
      <div
        class="w-full max-w-md bg-white dark:bg-slate-900 border-l border-slate-200 dark:border-slate-700 h-full flex flex-col overflow-hidden shadow-2xl"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-slate-200 dark:border-slate-700 shrink-0"
        >
          <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
            Configurações da Gamificação
          </h3>
          <button
            class="text-slate-400 hover:text-slate-600"
            @click="showSettings = false"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <div class="overflow-y-auto flex-1 px-5 py-5 space-y-6">
          <!-- Global goals -->
          <div>
            <p
              class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3"
            >
              Meta Geral do Time
            </p>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
                  >Meta de Faturamento (R$)</label
                >
                <input
                  v-model="editGlobal.team_goal_value"
                  type="number"
                  min="0"
                  placeholder="0"
                  class="w-full text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-1"
                  >Meta de Vendas (qtd)</label
                >
                <input
                  v-model="editGlobal.team_goal_won"
                  type="number"
                  min="0"
                  placeholder="0"
                  class="w-full text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>
            </div>
          </div>

          <!-- Individual goals -->
          <div>
            <p
              class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3"
            >
              Metas Individuais —
              {{
                new Date().toLocaleString('pt-BR', {
                  month: 'long',
                  year: 'numeric',
                })
              }}
            </p>
            <div class="space-y-3">
              <div
                v-for="agent in agents"
                :key="agent.id"
                class="p-3 rounded-lg bg-slate-50 dark:bg-slate-800 border border-slate-100 dark:border-slate-700"
              >
                <div class="flex items-center gap-2.5 mb-2">
                  <img
                    v-if="agent.avatar_url"
                    :src="agent.avatar_url"
                    class="size-7 rounded-full object-cover shrink-0"
                  />
                  <div
                    v-else
                    class="size-7 rounded-full bg-woot-100 dark:bg-woot-800 flex items-center justify-center text-[10px] font-bold text-woot-600 shrink-0"
                  >
                    {{ initials(agent.name) }}
                  </div>
                  <span
                    class="flex-1 text-xs font-medium text-slate-700 dark:text-slate-200 truncate"
                    >{{ agent.name }}</span
                  >
                </div>
                <div class="grid grid-cols-2 gap-2">
                  <div>
                    <label class="block text-[10px] text-slate-500 mb-1"
                      >Meta R$</label
                    >
                    <input
                      v-if="
                        editIndividualMap.value &&
                        editIndividualMap.value[agent.id]
                      "
                      v-model="editIndividualMap.value[agent.id].target_value"
                      type="number"
                      min="0"
                      placeholder="0"
                      class="w-full text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-1 focus:ring-woot-500"
                    />
                  </div>
                  <div>
                    <label class="block text-[10px] text-slate-500 mb-1"
                      >Meta Vendas</label
                    >
                    <input
                      v-if="
                        editIndividualMap.value &&
                        editIndividualMap.value[agent.id]
                      "
                      v-model="editIndividualMap.value[agent.id].target_won"
                      type="number"
                      min="0"
                      placeholder="0"
                      class="w-full text-xs border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-1.5 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-1 focus:ring-woot-500"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Scoring info -->
          <div
            class="rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700 p-4"
          >
            <p
              class="text-xs font-semibold text-amber-700 dark:text-amber-400 uppercase tracking-wide mb-1.5"
            >
              Regra de Pontuação
            </p>
            <p class="text-xs text-amber-700 dark:text-amber-400">
              Cada negócio <span class="font-bold">Ganho = 100 pontos</span> +
              bônus de 1pt por R$ 1.000 faturado. Apenas negócios marcados como
              Ganho são contabilizados.
            </p>
          </div>
        </div>

        <div
          class="px-5 py-3 bg-slate-50 dark:bg-slate-900 flex justify-end gap-2 border-t border-slate-200 dark:border-slate-700 shrink-0"
        >
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-slate-300 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-700 font-medium transition-colors"
            @click="showSettings = false"
          >
            Cancelar
          </button>
          <button
            :disabled="savingGoals"
            class="text-xs px-4 py-1.5 rounded-lg bg-woot-500 text-white hover:bg-woot-600 font-medium transition-colors disabled:opacity-50"
            @click="saveSettings"
          >
            {{ savingGoals ? 'Salvando...' : 'Salvar' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
