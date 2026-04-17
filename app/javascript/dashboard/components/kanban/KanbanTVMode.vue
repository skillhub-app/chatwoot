<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { gamificationAPI } from 'dashboard/api/kanban';

const rankings = ref([]);
const overview = ref(null);
const recentWins = ref([]);
const lastUpdated = ref(null);
const tick = ref(0);
let interval = null;

const MEDALS = ['🥇', '🥈', '🥉'];

async function loadData() {
  try {
    const [r, o, w] = await Promise.all([
      gamificationAPI.rankings(),
      gamificationAPI.overview(),
      gamificationAPI.recentWins(),
    ]);
    rankings.value = r.data.payload;
    overview.value = o.data.payload;
    recentWins.value = w.data.payload.slice(0, 8);
    lastUpdated.value = new Date().toLocaleTimeString('pt-BR');
    tick.value++;
  } catch {
    /* ignore */
  }
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
  return new Date(ts * 1000).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function exitTV() {
  // If opened in a new tab, close it; otherwise go back
  if (window.opener) {
    window.close();
  } else {
    window.history.back();
  }
}

function handleKey(e) {
  if (e.key === 'Escape') exitTV();
}

onMounted(() => {
  loadData();
  interval = setInterval(loadData, 30000); // refresh every 30s
  document.addEventListener('keydown', handleKey);
});

onUnmounted(() => {
  clearInterval(interval);
  document.removeEventListener('keydown', handleKey);
});
</script>

<template>
  <div
    class="fixed inset-0 bg-slate-950 text-white overflow-hidden flex flex-col select-none"
  >
    <!-- Top bar -->
    <div
      class="flex items-center justify-between px-8 py-3 bg-black/30 border-b border-white/10 shrink-0"
    >
      <div class="flex items-center gap-3">
        <span class="text-amber-400 text-2xl">🏆</span>
        <div>
          <h1 class="text-xl font-bold tracking-wide">RANKING DA EQUIPE</h1>
          <p class="text-xs text-slate-400">Chatwoot-Volponi · Kanban CRM</p>
        </div>
      </div>

      <!-- Live stats -->
      <div v-if="overview" class="flex items-center gap-6">
        <div class="text-center">
          <p class="text-2xl font-black text-green-400">
            {{ overview.today.won }}
          </p>
          <p class="text-[10px] text-slate-400 uppercase tracking-wide">
            Ganhos Hoje
          </p>
        </div>
        <div class="text-center">
          <p class="text-2xl font-black text-amber-400">
            {{ formatCurrency(overview.month.value) }}
          </p>
          <p class="text-[10px] text-slate-400 uppercase tracking-wide">
            Receita no Mês
          </p>
        </div>
        <div class="text-center">
          <p class="text-2xl font-black text-woot-400">
            {{ overview.total.open }}
          </p>
          <p class="text-[10px] text-slate-400 uppercase tracking-wide">
            Leads Abertos
          </p>
        </div>
      </div>

      <div class="flex items-center gap-3">
        <span class="text-xs text-slate-500"
          >Atualizado: {{ lastUpdated }}</span
        >
        <button
          class="text-xs px-3 py-1.5 rounded-lg border border-white/20 text-slate-300 hover:bg-white/10 transition-colors"
          @click="exitTV"
        >
          ESC Sair
        </button>
      </div>
    </div>

    <!-- Main content -->
    <div class="flex-1 flex gap-0 overflow-hidden">
      <!-- Ranking column -->
      <div
        class="w-[55%] border-r border-white/10 flex flex-col p-6 overflow-hidden"
      >
        <h2
          class="text-sm font-semibold text-slate-400 uppercase tracking-widest mb-4"
        >
          Ranking de Pontos
        </h2>
        <div class="flex flex-col gap-3 overflow-y-auto flex-1">
          <div
            v-for="(agent, idx) in rankings"
            :key="agent.agent.id"
            class="flex items-center gap-4 rounded-xl px-4 py-3 border transition-all"
            :class="[
              idx === 0
                ? 'bg-amber-500/10 border-amber-500/30'
                : idx === 1
                  ? 'bg-slate-400/10 border-slate-400/20'
                  : idx === 2
                    ? 'bg-amber-800/10 border-amber-700/20'
                    : 'bg-white/5 border-white/10',
            ]"
          >
            <!-- Rank -->
            <div class="w-10 text-center shrink-0">
              <span v-if="idx < 3" class="text-2xl">{{ MEDALS[idx] }}</span>
              <span v-else class="text-lg font-black text-slate-400">{{
                idx + 1
              }}</span>
            </div>

            <!-- Avatar -->
            <img
              v-if="agent.agent.avatar_url"
              :src="agent.agent.avatar_url"
              class="size-10 rounded-full shrink-0"
              :class="idx === 0 ? 'ring-2 ring-amber-400' : ''"
            />
            <div
              v-else
              class="size-10 rounded-full bg-slate-700 flex items-center justify-center text-lg shrink-0"
            >
              {{ agent.agent.name.charAt(0).toUpperCase() }}
            </div>

            <!-- Name + badges -->
            <div class="flex-1 min-w-0">
              <p
                class="font-bold truncate"
                :class="idx === 0 ? 'text-lg text-amber-300' : 'text-white'"
              >
                {{ agent.agent.name }}
              </p>
              <div class="flex gap-3 mt-0.5">
                <span class="text-xs text-slate-400">
                  <span class="text-green-400 font-bold">{{
                    agent.stats.won
                  }}</span>
                  ganhos
                </span>
                <span class="text-xs text-slate-400">
                  {{ agent.stats.conversion_rate }}% conv.
                </span>
                <span class="text-xs text-amber-400 font-semibold">
                  {{ formatCurrency(agent.stats.value) }}
                </span>
              </div>
            </div>

            <!-- Points bar + score -->
            <div class="shrink-0 flex items-center gap-3">
              <div class="w-24 h-2 bg-slate-700 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full transition-all duration-700"
                  :class="idx === 0 ? 'bg-amber-400' : 'bg-woot-500'"
                  :style="{
                    width:
                      (rankings[0]?.points > 0
                        ? (agent.points / rankings[0].points) * 100
                        : 0) + '%',
                  }"
                />
              </div>
              <span
                class="text-lg font-black w-16 text-right"
                :class="idx === 0 ? 'text-amber-400' : 'text-slate-200'"
              >
                {{ agent.points }}
              </span>
              <span class="text-xs text-slate-500">pts</span>
            </div>
          </div>
          <div
            v-if="!rankings.length"
            class="text-center py-12 text-slate-600 text-sm"
          >
            Sem dados de ranking ainda
          </div>
        </div>
      </div>

      <!-- Right column: Recent wins + stats -->
      <div class="flex-1 flex flex-col p-6 gap-4 overflow-hidden">
        <!-- Month stats strip -->
        <div v-if="overview" class="grid grid-cols-3 gap-3 shrink-0">
          <div
            class="bg-green-500/10 border border-green-500/20 rounded-xl p-3 text-center"
          >
            <p class="text-2xl font-black text-green-400">
              {{ overview.month.won }}
            </p>
            <p class="text-[10px] text-slate-400 uppercase">Ganhos no Mês</p>
          </div>
          <div
            class="bg-woot-500/10 border border-woot-500/20 rounded-xl p-3 text-center"
          >
            <p class="text-2xl font-black text-woot-400">
              {{ overview.month.new }}
            </p>
            <p class="text-[10px] text-slate-400 uppercase">Novos Leads</p>
          </div>
          <div
            class="bg-red-500/10 border border-red-500/20 rounded-xl p-3 text-center"
          >
            <p class="text-2xl font-black text-red-400">
              {{ overview.total.lost }}
            </p>
            <p class="text-[10px] text-slate-400 uppercase">Perdidos</p>
          </div>
        </div>

        <!-- Recent wins -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <h2
            class="text-sm font-semibold text-slate-400 uppercase tracking-widest mb-3 shrink-0"
          >
            🏆 Últimas Vitórias
          </h2>
          <div class="flex flex-col gap-2 overflow-y-auto flex-1">
            <div
              v-for="win in recentWins"
              :key="win.id"
              class="flex items-center gap-3 bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 hover:bg-white/8 transition-colors"
              :style="{
                borderLeftColor: win.stage_color,
                borderLeftWidth: '3px',
              }"
            >
              <img
                v-if="win.assignee?.avatar_url"
                :src="win.assignee.avatar_url"
                class="size-8 rounded-full shrink-0"
              />
              <div
                v-else
                class="size-8 rounded-full bg-green-900/50 flex items-center justify-center text-sm shrink-0"
              >
                🏆
              </div>

              <div class="flex-1 min-w-0">
                <p class="text-sm font-semibold text-white truncate">
                  {{ win.title }}
                </p>
                <p class="text-[10px] text-slate-500">
                  {{ win.assignee?.name || '—' }} · {{ win.pipeline_name }}
                </p>
              </div>

              <div class="text-right shrink-0">
                <p class="text-sm font-bold text-green-400">
                  {{ formatCurrency(win.value) }}
                </p>
                <p class="text-[10px] text-slate-500">
                  {{ formatDate(win.won_at) }}
                </p>
              </div>
            </div>
            <div
              v-if="!recentWins.length"
              class="text-center py-8 text-slate-600 text-sm"
            >
              Nenhuma vitória registrada ainda
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Bottom ticker -->
    <div
      class="shrink-0 bg-black/40 border-t border-white/10 px-6 py-2 flex items-center gap-4"
    >
      <span class="text-xs text-slate-500 uppercase tracking-widest shrink-0"
        >LIVE</span
      >
      <div class="flex items-center gap-1.5 overflow-hidden flex-1">
        <template v-for="win in recentWins.slice(0, 5)" :key="win.id">
          <span class="text-xs text-green-400 whitespace-nowrap"
            >🏆 {{ win.title }}</span
          >
          <span class="text-slate-600">·</span>
          <span class="text-xs text-slate-400 whitespace-nowrap">{{
            win.assignee?.name
          }}</span>
          <span class="text-xs text-amber-400 whitespace-nowrap">{{
            formatCurrency(win.value)
          }}</span>
          <span class="text-slate-700 mx-2">|</span>
        </template>
      </div>
      <div class="flex items-center gap-1 shrink-0">
        <span class="size-1.5 rounded-full bg-green-500 animate-pulse" />
        <span class="text-[10px] text-slate-500"
          >Ao vivo · atualiza a cada 30s</span
        >
      </div>
    </div>
  </div>
</template>
