<!-- eslint-disable vue/no-bare-strings-in-template, prettier/prettier -->
<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const store    = useStore();
const router   = useRouter();
const { accountId } = useAccount();

const instanceName  = ref('');
const instanceToken = ref('');
const phoneNumber   = ref('');
const creating      = ref(false);
const inboxId       = ref(null);
const webhookUrl    = ref('');
const qrCode        = ref(null);
const qrError       = ref(null);
const qrLoading     = ref(false);
const connected     = ref(false);
let pollInterval    = null;

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

async function fetchQr() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/inboxes/${inboxId.value}/uazapi_qr`
    );
    if (data.error) {
      qrError.value = data.error;
      return null;
    }
    qrError.value = null;
    return data;
  } catch (err) {
    qrError.value = err?.response?.data?.error || err.message || 'Erro ao obter QR code';
    return null;
  }
}

function stopPolling() {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
}

async function checkConnection() {
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/inboxes/${inboxId.value}/uazapi_status`
    );
    if (data?.connection_status === 'connected') {
      connected.value = true;
      stopPolling();
    } else {
      const qrData = await fetchQr();
      if (qrData?.base64) {
        qrCode.value = qrData.base64;
      }
    }
  } catch {
    // ignore polling errors silently
  }
}

function startPolling() {
  pollInterval = setInterval(checkConnection, 8000);
}

async function loadQrCode() {
  qrLoading.value = true;
  try {
    const qrData = await fetchQr();
    if (qrData?.base64) {
      qrCode.value = qrData.base64;
    }
  } finally {
    qrLoading.value = false;
  }
}

async function retryQr() {
  qrCode.value = null;
  qrError.value = null;
  await loadQrCode();
}

async function createChannel() {
  if (!instanceName.value.trim()) {
    useAlert('Nome da instância é obrigatório');
    return;
  }
  if (!instanceToken.value.trim()) {
    useAlert('Token da instância é obrigatório. Copie o token do painel UAZAPI.');
    return;
  }
  creating.value = true;
  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: instanceName.value,
      channel: {
        type: 'uazapi',
        uazapi_instance_name:  instanceName.value.trim(),
        uazapi_instance_token: instanceToken.value.trim(),
        phone_number: phoneNumber.value.trim() || undefined,
      },
    });
    inboxId.value = inbox.id;
    try {
      const { data: whData } = await window.axios.get(
        `/api/v1/accounts/${accountId.value}/inboxes/${inbox.id}/uazapi_webhook_url`
      );
      webhookUrl.value = whData.webhook_url || '';
    } catch {
      webhookUrl.value = '';
    }
    await loadQrCode();
    startPolling();
  } catch (err) {
    useAlert(err.message || 'Erro ao criar instância UAZAPI');
  } finally {
    creating.value = false;
  }
}

function copyWebhook() {
  if (webhookUrl.value) {
    navigator.clipboard.writeText(webhookUrl.value);
    useAlert('URL copiada!');
  }
}

function goToAgents() {
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: inboxId.value },
  });
}

onBeforeUnmount(() => stopPolling());
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      header-title="WhatsApp UAZAPI"
      header-content="Conecte um WhatsApp não oficial via UAZAPI. Crie a instância no painel UAZAPI, copie o token e cole aqui."
    />

    <!-- Step 1: Create inbox -->
    <div v-if="!inboxId">
      <!-- Instructions -->
      <div
        class="mb-6 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800 text-sm text-blue-700 dark:text-blue-300"
      >
        <p class="font-semibold mb-2">Como conectar:</p>
        <ol class="list-decimal ml-4 space-y-1">
          <li>Acesse o painel UAZAPI e crie uma instância</li>
          <li>Copie o <strong>token</strong> da instância criada</li>
          <li>Preencha os campos abaixo e clique em "Criar e conectar"</li>
          <li>Configure o webhook da instância no painel UAZAPI</li>
        </ol>
      </div>

      <form
        class="flex flex-wrap flex-col mx-0"
        @submit.prevent="createChannel"
      >
        <div class="flex-shrink-0 flex-grow-0 mb-4">
          <label>
            Nome da instância <span class="text-red-500">*</span>
            <input
              v-model="instanceName"
              type="text"
              placeholder="ex: volponi-suporte"
              required
            />
          </label>
          <p class="help-text">
            Deve ser exatamente o nome da instância no painel UAZAPI.
          </p>
        </div>

        <div class="flex-shrink-0 flex-grow-0 mb-4">
          <label>
            Token da instância <span class="text-red-500">*</span>
            <input
              v-model="instanceToken"
              type="text"
              placeholder="Cole o token da instância UAZAPI"
              required
            />
          </label>
          <p class="help-text">
            Encontrado no painel UAZAPI → sua instância → Token.
          </p>
        </div>

        <div class="flex-shrink-0 flex-grow-0 mb-4">
          <label>
            Número de telefone (opcional)
            <input
              v-model="phoneNumber"
              type="text"
              placeholder="5511999999999"
            />
          </label>
          <p class="help-text">Número do WhatsApp que será conectado.</p>
        </div>

        <div class="w-full mt-4">
          <NextButton
            :is-loading="uiFlags.isCreating || creating"
            type="submit"
            solid
            blue
            label="Criar e conectar"
          />
        </div>
      </form>
    </div>

    <!-- Step 2: QR Code / connected -->
    <div v-else class="mt-6 flex flex-col items-center gap-6">
      <div v-if="connected" class="flex flex-col items-center gap-4">
        <span class="i-lucide-check-circle size-16 text-emerald-500" />
        <p class="text-base font-semibold text-emerald-600">
          WhatsApp conectado com sucesso!
        </p>
        <NextButton solid blue label="Adicionar agentes" @click="goToAgents" />
      </div>

      <div v-else class="flex flex-col items-center gap-4 w-full max-w-sm">
        <p class="text-sm text-slate-600 dark:text-slate-300 text-center">
          Escaneie o QR code com o WhatsApp para conectar.
        </p>

        <div
          v-if="qrLoading"
          class="size-48 flex items-center justify-center bg-slate-100 dark:bg-slate-800 rounded-lg"
        >
          <span
            class="i-lucide-loader-circle animate-spin size-8 text-slate-400"
          />
        </div>

        <img
          v-else-if="qrCode"
          :src="qrCode"
          alt="QR Code WhatsApp"
          class="size-48 rounded-lg border border-slate-200"
        />

        <div
          v-else-if="qrError"
          class="flex flex-col items-center gap-3 p-4 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800 w-full text-center"
        >
          <span class="i-lucide-alert-circle size-8 text-red-500" />
          <p class="text-xs text-red-600 dark:text-red-400 break-words">
            {{ qrError }}
          </p>
          <NextButton
            size="small"
            solid
            red
            label="Tentar novamente"
            @click="retryQr"
          />
        </div>

        <div
          v-else
          class="size-48 flex items-center justify-center bg-slate-100 dark:bg-slate-800 rounded-lg text-slate-400 text-xs text-center px-4"
        >
          Aguardando QR code...
        </div>

        <!-- Webhook instructions -->
        <div
          class="w-full p-3 bg-amber-50 dark:bg-amber-900/20 rounded-lg border border-amber-200 dark:border-amber-800 text-xs"
        >
          <p class="font-semibold text-amber-700 dark:text-amber-400 mb-1">
            Configure o webhook no painel UAZAPI:
          </p>
          <p class="text-amber-600 dark:text-amber-400 mb-2">
            Eventos:
            <code class="bg-amber-100 dark:bg-amber-800 px-1 rounded"
              >MESSAGES_UPSERT</code
            >,
            <code class="bg-amber-100 dark:bg-amber-800 px-1 rounded"
              >CONNECTION_UPDATE</code
            >
          </p>
          <div v-if="webhookUrl" class="flex items-center gap-2 mt-1">
            <code
              class="flex-1 bg-amber-100 dark:bg-amber-800 px-2 py-1 rounded break-all text-amber-800 dark:text-amber-200 select-all"
            >
              {{ webhookUrl }}
            </code>
            <button
              type="button"
              class="shrink-0 text-amber-700 dark:text-amber-400 hover:text-amber-900"
              @click="copyWebhook"
            >
              <span class="i-lucide-copy size-4" />
            </button>
          </div>
        </div>

        <p v-if="!qrError" class="text-[11px] text-slate-400">
          Verificando a cada 8 segundos...
        </p>
      </div>
    </div>
  </div>
</template>
