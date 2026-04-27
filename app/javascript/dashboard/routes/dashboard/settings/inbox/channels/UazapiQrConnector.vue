<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  inboxId: { type: Number, required: true },
});

const { accountId } = useAccount();

const connectionStatus = ref('unknown');
const qrCode = ref(null);
const qrLoading = ref(false);
const actionLoading = ref(false);
let pollInterval = null;

const baseUrl = computed(
  () => `/api/v1/accounts/${accountId.value}/inboxes/${props.inboxId}`
);

const isConnected = computed(
  () =>
    connectionStatus.value === 'open' || connectionStatus.value === 'connected'
);

async function fetchStatus() {
  try {
    const { data } = await window.axios.get(`${baseUrl.value}/uazapi_status`);
    connectionStatus.value = data.connection_status || 'unknown';
  } catch {
    connectionStatus.value = 'unknown';
  }
}

function stopPolling() {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
}

function startPolling() {
  stopPolling();
  pollInterval = setInterval(async () => {
    await fetchStatus();
    if (isConnected.value) {
      qrCode.value = null;
      stopPolling();
    }
  }, 8000);
}

async function generateQr() {
  qrLoading.value = true;
  qrCode.value = null;
  try {
    const { data } = await window.axios.get(`${baseUrl.value}/uazapi_qr`);
    if (data?.base64) qrCode.value = data.base64;
    startPolling();
  } catch (e) {
    useAlert(e.response?.data?.error || 'Erro ao gerar QR Code');
  } finally {
    qrLoading.value = false;
  }
}

async function reconnect() {
  actionLoading.value = true;
  try {
    await window.axios.post(`${baseUrl.value}/uazapi_reconnect`);
    useAlert('Reconectando...');
    setTimeout(fetchStatus, 3000);
  } catch (e) {
    useAlert(e.response?.data?.error || 'Erro ao reconectar');
  } finally {
    actionLoading.value = false;
  }
}

async function logout() {
  actionLoading.value = true;
  try {
    await window.axios.delete(`${baseUrl.value}/uazapi_logout`);
    connectionStatus.value = 'close';
    qrCode.value = null;
    stopPolling();
    useAlert('Desconectado com sucesso');
  } catch (e) {
    useAlert(e.response?.data?.error || 'Erro ao desconectar');
  } finally {
    actionLoading.value = false;
  }
}

fetchStatus();

onBeforeUnmount(() => stopPolling());
</script>

<template>
  <div class="p-6 max-w-xl">
    <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100 mb-1">
      QR Code Connector
    </h3>
    <p class="text-sm text-slate-500 dark:text-slate-400 mb-6">
      Gere o QR Code para conectar seu WhatsApp
    </p>

    <div class="flex items-center gap-2 mb-6">
      <span
        class="inline-block size-3 rounded-full"
        :class="isConnected ? 'bg-emerald-500' : 'bg-red-500'"
      />
      <span class="text-sm font-medium text-slate-700 dark:text-slate-300">
        {{ isConnected ? 'Connected' : 'Disconnected' }}
      </span>
    </div>

    <div
      v-if="qrLoading"
      class="mb-6 size-48 flex items-center justify-center bg-slate-100 dark:bg-slate-800 rounded-lg"
    >
      <span class="i-lucide-loader-circle animate-spin size-8 text-slate-400" />
    </div>
    <img
      v-else-if="qrCode"
      :src="qrCode"
      alt="QR Code"
      class="mb-6 size-48 rounded-lg border border-slate-200 dark:border-slate-700"
    />

    <div class="flex gap-3 flex-wrap">
      <button
        class="px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium disabled:opacity-50"
        :disabled="actionLoading || qrLoading"
        @click="generateQr"
      >
        Generate QR Code
      </button>
      <button
        class="px-4 py-2 rounded-lg bg-amber-500 hover:bg-amber-600 text-white text-sm font-medium disabled:opacity-50"
        :disabled="actionLoading"
        @click="reconnect"
      >
        Reconnect
      </button>
      <button
        class="px-4 py-2 rounded-lg bg-red-500 hover:bg-red-600 text-white text-sm font-medium disabled:opacity-50"
        :disabled="actionLoading"
        @click="logout"
      >
        Logout
      </button>
    </div>
  </div>
</template>
