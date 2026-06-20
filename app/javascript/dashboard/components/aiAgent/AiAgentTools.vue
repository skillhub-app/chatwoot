<!-- eslint-disable vue/no-bare-strings-in-template, prettier/prettier -->
<script setup>
import { ref, onMounted } from 'vue';
import aiAgentsAPI from '../../api/aiAgents';

const props = defineProps({
  agentId: { type: Number, required: true },
});

const tools      = ref([]);
const loading    = ref(false);
const showForm   = ref(false);
const editingTool = ref(null);
const testResult  = ref(null);
const testLoading = ref(false);
const testParams  = ref('{}');
const showTest    = ref(false);
const saveError   = ref(null);

const HTTP_METHODS = ['POST', 'GET', 'PUT', 'PATCH', 'DELETE'];

const emptyForm = () => ({
  name:                  '',
  description:           '',
  http_method:           'POST',
  endpoint_url:          '',
  parameters_schema:     '{\n  "type": "object",\n  "properties": {},\n  "required": []\n}',
  headers:               '{}',
  request_body_template: '',
  response_template:     '',
  when_to_use:           '',
  timeout_seconds:       10,
  active:                true,
  position:              0,
});

const form = ref(emptyForm());

async function load() {
  loading.value = true;
  try {
    const { data } = await aiAgentsAPI.getTools(props.agentId);
    tools.value = data.payload;
  } finally {
    loading.value = false;
  }
}

function openCreate() {
  editingTool.value = null;
  form.value = emptyForm();
  form.value.position = tools.value.length + 1;
  saveError.value = null;
  showForm.value = true;
}

function openEdit(t) {
  editingTool.value = t;
  form.value = {
    ...t,
    parameters_schema: JSON.stringify(t.parameters_schema || {}, null, 2),
    headers:           JSON.stringify(t.headers || {}, null, 2),
  };
  saveError.value = null;
  showForm.value = true;
}

function buildPayload() {
  let parametersSchema = {};
  let headers = {};
  try { parametersSchema = JSON.parse(form.value.parameters_schema || '{}'); } catch { /* noop */ }
  try { headers = JSON.parse(form.value.headers || '{}'); } catch { /* noop */ }
  return {
    ...form.value,
    parameters_schema: parametersSchema,
    headers,
  };
}

async function save() {
  saveError.value = null;
  const payload = buildPayload();
  try {
    if (editingTool.value) {
      await aiAgentsAPI.updateTool(props.agentId, editingTool.value.id, payload);
    } else {
      await aiAgentsAPI.createTool(props.agentId, payload);
    }
    showForm.value = false;
    await load();
  } catch (err) {
    saveError.value = err?.response?.data?.error || 'Erro ao salvar ferramenta';
  }
}

async function remove(t) {
  if (!window.confirm(`Remover a ferramenta "${t.name}"?`)) return;
  await aiAgentsAPI.deleteTool(props.agentId, t.id);
  await load();
}

async function toggleActive(t) {
  await aiAgentsAPI.updateTool(props.agentId, t.id, { active: !t.active });
  await load();
}

function openTest(t) {
  editingTool.value = t;
  testParams.value  = '{}';
  testResult.value  = null;
  showTest.value    = true;
}

async function runTest() {
  testLoading.value = true;
  testResult.value  = null;
  let parsedParams = {};
  try { parsedParams = JSON.parse(testParams.value || '{}'); } catch { /* noop */ }
  try {
    const { data } = await aiAgentsAPI.testTool(props.agentId, editingTool.value.id, parsedParams);
    testResult.value = data.payload;
  } catch (err) {
    testResult.value = { success: false, error_message: err?.response?.data?.error || err.message };
  } finally {
    testLoading.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h3 class="text-sm font-semibold text-slate-800 dark:text-slate-100">
          Ferramentas (Tools)
        </h3>
        <p class="text-xs text-slate-500 mt-0.5">
          Webhooks externos que o agente pode chamar via function calling para
          buscar dados em tempo real.
        </p>
      </div>
      <button
        class="px-3 py-1.5 text-sm rounded bg-woot-500 hover:bg-woot-600 text-white"
        @click="openCreate"
      >
        + Nova ferramenta
      </button>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="text-center py-8 text-slate-400 text-sm">
      Carregando...
    </div>

    <!-- Empty -->
    <div
      v-else-if="tools.length === 0"
      class="text-center py-8 text-slate-400 text-sm"
    >
      Nenhuma ferramenta configurada. Adicione webhooks externos que o agente
      poderá consultar.
    </div>

    <!-- List -->
    <div v-else class="flex flex-col gap-2">
      <div
        v-for="t in tools"
        :key="t.id"
        class="border border-slate-200 dark:border-slate-700 rounded-lg p-4 bg-white dark:bg-slate-800"
        :class="{ 'opacity-50': !t.active }"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span
                class="text-xs font-mono bg-indigo-100 dark:bg-indigo-900/30 text-indigo-700 dark:text-indigo-300 px-2 py-0.5 rounded font-semibold"
              >
                {{ t.name }}
              </span>
              <span
                class="text-xs px-2 py-0.5 rounded bg-slate-100 dark:bg-slate-700 text-slate-500"
              >
                {{ t.http_method }}
              </span>
              <span
                v-if="t.is_native"
                class="text-xs px-2 py-0.5 rounded bg-emerald-100 dark:bg-emerald-900/30 text-emerald-700 dark:text-emerald-300 font-semibold"
                title="Ferramenta nativa gerenciada pelo sistema (URL e schema fixos)"
              >
                Nativa
              </span>
              <span
                v-if="!t.active"
                class="text-xs px-2 py-0.5 rounded bg-amber-100 text-amber-600"
              >
                inativa
              </span>
            </div>
            <p class="text-sm text-slate-700 dark:text-slate-200">
              {{ t.description }}
            </p>
            <p class="text-xs text-slate-400 mt-0.5 truncate font-mono">
              {{ t.endpoint_url }}
            </p>
            <p v-if="t.when_to_use" class="text-xs text-slate-500 mt-1 italic">
              Usar quando: {{ t.when_to_use }}
            </p>
          </div>
          <div class="flex gap-1 shrink-0">
            <button
              class="px-2 py-1 text-xs rounded border border-slate-200 dark:border-slate-600 hover:bg-slate-50 dark:hover:bg-slate-700 text-slate-600 dark:text-slate-300"
              title="Testar ferramenta"
              @click="openTest(t)"
            >
              ▷ Testar
            </button>
            <button
              class="w-8 h-8 flex items-center justify-center rounded hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-500"
              :title="t.active ? 'Desativar' : 'Ativar'"
              @click="toggleActive(t)"
            >
              {{ t.active ? '⏸' : '▶' }}
            </button>
            <button
              class="w-8 h-8 flex items-center justify-center rounded hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-500"
              title="Editar"
              @click="openEdit(t)"
            >
              ✎
            </button>
            <button
              v-if="!t.is_native"
              class="w-8 h-8 flex items-center justify-center rounded hover:bg-red-50 dark:hover:bg-red-900/20 text-red-400"
              title="Remover"
              @click="remove(t)"
            >
              ✕
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ── Form modal ──────────────────────────────────────────────────────── -->
    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      @click.self="showForm = false"
    >
      <div
        class="bg-white dark:bg-slate-800 rounded-xl shadow-xl w-full max-w-2xl mx-4 max-h-[90vh] overflow-y-auto p-6"
      >
        <h4
          class="text-base font-semibold text-slate-800 dark:text-slate-100 mb-4"
        >
          {{ editingTool ? 'Editar ferramenta' : 'Nova ferramenta' }}
        </h4>

        <div class="flex flex-col gap-4">
          <!-- Aviso ferramenta nativa -->
          <div
            v-if="form.is_native"
            class="text-xs rounded-lg px-3 py-2 bg-emerald-50 dark:bg-emerald-900/20 text-emerald-700 dark:text-emerald-300 border border-emerald-200 dark:border-emerald-800"
          >
            Ferramenta <strong>nativa</strong> gerenciada pelo sistema. URL e
            schema são fixos; você pode apenas ativar/desativar.
          </div>
          <!-- Name -->
          <label class="flex flex-col gap-1">
            <span
              class="text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              Nome da função <span class="text-red-400">*</span>
            </span>
            <input
              v-model="form.name"
              type="text"
              :disabled="form.is_native"
              :readonly="form.is_native"
              placeholder="ex: consultar_estoque"
              class="text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 disabled:opacity-60 disabled:cursor-not-allowed"
            />
            <span class="text-xs text-slate-400"
              >snake_case, apenas letras minúsculas, números e _ — este é o nome
              que o LLM vai usar.</span
            >
          </label>

          <!-- Description -->
          <label class="flex flex-col gap-1">
            <span
              class="text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              Descrição <span class="text-red-400">*</span>
            </span>
            <textarea
              v-model="form.description"
              rows="2"
              placeholder="O que esta ferramenta faz? (lido pelo LLM para decidir quando chamar)"
              class="text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 resize-none"
            />
          </label>

          <!-- When to use -->
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-slate-600 dark:text-slate-300"
              >Quando usar (opcional)</span
            >
            <input
              v-model="form.when_to_use"
              type="text"
              placeholder="ex: Sempre que o cliente perguntar sobre disponibilidade de produto"
              class="text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400"
            />
          </label>

          <!-- HTTP method + URL -->
          <div class="flex gap-2">
            <label class="flex flex-col gap-1 w-28 shrink-0">
              <span
                class="text-xs font-medium text-slate-600 dark:text-slate-300"
                >Método</span
              >
              <select
                v-model="form.http_method"
                :disabled="form.is_native"
                class="text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-2 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 disabled:opacity-60 disabled:cursor-not-allowed"
              >
                <option v-for="m in HTTP_METHODS" :key="m" :value="m">
                  {{ m }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 flex-1">
              <span
                class="text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                URL do endpoint <span class="text-red-400">*</span>
              </span>
              <input
                v-model="form.endpoint_url"
                type="url"
                :disabled="form.is_native"
                :readonly="form.is_native"
                placeholder="https://minha-api.com/webhook"
                class="text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 disabled:opacity-60 disabled:cursor-not-allowed"
              />
            </label>
          </div>

          <!-- Parameters schema -->
          <label class="flex flex-col gap-1">
            <span
              class="text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              Parâmetros (JSON Schema)
            </span>
            <textarea
              v-model="form.parameters_schema"
              rows="5"
              :disabled="form.is_native"
              :readonly="form.is_native"
              class="text-xs font-mono border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-slate-50 dark:bg-slate-900 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 resize-y disabled:opacity-60 disabled:cursor-not-allowed"
            />
            <span class="text-xs text-slate-400"
              >JSON Schema descrevendo os parâmetros que o LLM pode
              passar.</span
            >
          </label>

          <!-- Headers -->
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-slate-600 dark:text-slate-300"
              >Headers (JSON)</span
            >
            <textarea
              v-model="form.headers"
              rows="3"
              placeholder='{"Authorization": "Bearer seu-token"}'
              class="text-xs font-mono border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-slate-50 dark:bg-slate-900 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 resize-y"
            />
          </label>

          <!-- Body template -->
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-slate-600 dark:text-slate-300"
              >Template do body (opcional)</span
            >
            <textarea
              v-model="form.request_body_template"
              rows="3"
              placeholder='{"produto": "{{produto}}", "quantidade": {{quantidade}}}'
              class="text-xs font-mono border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-slate-50 dark:bg-slate-900 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 resize-y"
            />
            <span class="text-xs text-slate-400">
              Use &#123;&#123;variavel&#125;&#125; para interpolar parâmetros do
              LLM. Deixe vazio para enviar todos os parâmetros como JSON.
            </span>
          </label>

          <!-- Response template -->
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-slate-600 dark:text-slate-300"
              >Template de resposta (opcional)</span
            >
            <textarea
              v-model="form.response_template"
              rows="2"
              placeholder="Estoque de {{nome}}: {{quantidade}} unidades"
              class="text-xs font-mono border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-slate-50 dark:bg-slate-900 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 resize-y"
            />
            <span class="text-xs text-slate-400"
              >Formata o retorno para o LLM. Deixe vazio para enviar o JSON
              bruto.</span
            >
          </label>

          <!-- Timeout + active + position -->
          <div class="flex gap-4 items-end">
            <label class="flex flex-col gap-1 w-32">
              <span
                class="text-xs font-medium text-slate-600 dark:text-slate-300"
                >Timeout (segundos)</span
              >
              <input
                v-model.number="form.timeout_seconds"
                type="number"
                min="1"
                max="60"
                class="text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400"
              />
            </label>
            <label class="flex flex-col gap-1 w-24">
              <span
                class="text-xs font-medium text-slate-600 dark:text-slate-300"
                >Posição</span
              >
              <input
                v-model.number="form.position"
                type="number"
                min="0"
                class="text-sm border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400"
              />
            </label>
            <label class="flex items-center gap-2 pb-2 cursor-pointer">
              <input
                v-model="form.active"
                type="checkbox"
                class="w-4 h-4 rounded accent-woot-500"
              />
              <span class="text-sm text-slate-700 dark:text-slate-300"
                >Ativa</span
              >
            </label>
          </div>

          <!-- Error -->
          <p
            v-if="saveError"
            class="text-xs text-red-500 bg-red-50 dark:bg-red-900/20 px-3 py-2 rounded"
          >
            {{ saveError }}
          </p>
        </div>

        <div class="flex justify-end gap-2 mt-6">
          <button
            class="px-4 py-2 text-sm rounded border border-slate-300 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
            @click="showForm = false"
          >
            Cancelar
          </button>
          <button
            class="px-4 py-2 text-sm rounded bg-woot-500 hover:bg-woot-600 text-white"
            @click="save"
          >
            Salvar
          </button>
        </div>
      </div>
    </div>

    <!-- ── Test modal ──────────────────────────────────────────────────────── -->
    <div
      v-if="showTest"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      @click.self="showTest = false"
    >
      <div
        class="bg-white dark:bg-slate-800 rounded-xl shadow-xl w-full max-w-lg mx-4 p-6"
      >
        <h4
          class="text-base font-semibold text-slate-800 dark:text-slate-100 mb-1"
        >
          Testar:
          <span class="font-mono text-indigo-600">{{ editingTool?.name }}</span>
        </h4>
        <p class="text-xs text-slate-400 mb-4">
          Esta chamada não cria registro de execução no log.
        </p>

        <label class="flex flex-col gap-1 mb-3">
          <span class="text-xs font-medium text-slate-600 dark:text-slate-300"
            >Parâmetros (JSON)</span
          >
          <textarea
            v-model="testParams"
            rows="5"
            class="text-xs font-mono border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 bg-slate-50 dark:bg-slate-900 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-400 resize-y"
          />
        </label>

        <button
          class="w-full py-2 text-sm rounded bg-woot-500 hover:bg-woot-600 text-white mb-4"
          :disabled="testLoading"
          @click="runTest"
        >
          {{ testLoading ? 'Executando...' : '▷ Executar' }}
        </button>

        <div
          v-if="testResult"
          class="border border-slate-200 dark:border-slate-700 rounded-lg p-3"
        >
          <div class="flex items-center gap-2 mb-2">
            <span
              class="text-xs font-semibold px-2 py-0.5 rounded"
              :class="
                testResult.success
                  ? 'bg-emerald-100 text-emerald-700'
                  : 'bg-red-100 text-red-600'
              "
            >
              {{ testResult.success ? '✓ Sucesso' : '✗ Erro' }}
            </span>
            <span v-if="testResult.http_status" class="text-xs text-slate-400"
              >HTTP {{ testResult.http_status }}</span
            >
            <span v-if="testResult.duration_ms" class="text-xs text-slate-400"
              >{{ testResult.duration_ms }}ms</span
            >
          </div>
          <p v-if="testResult.error_message" class="text-xs text-red-500 mb-2">
            {{ testResult.error_message }}
          </p>
          <div v-if="testResult.formatted_for_llm" class="mb-2">
            <p class="text-xs font-medium text-slate-500 mb-1">
              Formatado para o LLM:
            </p>
            <pre
              class="text-xs bg-slate-50 dark:bg-slate-900 p-2 rounded overflow-x-auto"
              >{{ testResult.formatted_for_llm }}</pre
            >
          </div>
          <div
            v-if="testResult.output && Object.keys(testResult.output).length"
          >
            <p class="text-xs font-medium text-slate-500 mb-1">Resposta raw:</p>
            <pre
              class="text-xs bg-slate-50 dark:bg-slate-900 p-2 rounded overflow-x-auto"
              >{{ JSON.stringify(testResult.output, null, 2) }}</pre
            >
          </div>
        </div>

        <div class="flex justify-end mt-4">
          <button
            class="px-4 py-2 text-sm rounded border border-slate-300 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
            @click="showTest = false"
          >
            Fechar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
