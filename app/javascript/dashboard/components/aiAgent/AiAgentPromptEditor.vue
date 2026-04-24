<!-- eslint-disable vue/no-bare-strings-in-template, prettier/prettier -->
<script setup>
import { ref, watch } from 'vue';
import aiAgentsAPI from '../../api/aiAgents';

const props = defineProps({ agent: { type: Object, required: true } });
const emit = defineEmits(['updated']);

const saving = ref(false);
const saved = ref(false);
const error = ref(null);

const DEFAULT_PROMPT = {
  name: '',
  company: '',
  objectives: [],
  business: { name: '', description: '', target_audience: '' },
  products: [],
  personality: [],
  rules: [],
  flow: [],
};

function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

const form = ref(deepClone({ ...DEFAULT_PROMPT, ...props.agent.prompt }));

watch(
  () => props.agent,
  a => {
    form.value = deepClone({ ...DEFAULT_PROMPT, ...a.prompt });
  }
);

// ── Lists (objectives, personality, rules) ───────────────────────────────────
function addItem(list) {
  list.push('');
}
function removeItem(list, i) {
  list.splice(i, 1);
}

// ── Products ─────────────────────────────────────────────────────────────────
function addProduct() {
  form.value.products.push({
    name: '',
    description: '',
    value: '',
    target_audience: '',
  });
}
function removeProduct(i) {
  form.value.products.splice(i, 1);
}

// ── Flow ─────────────────────────────────────────────────────────────────────
function addStep() {
  form.value.flow.push({
    title: '',
    instruction: '',
    example: '',
    substeps: [],
    branches: [],
  });
}
function removeStep(i) {
  form.value.flow.splice(i, 1);
}
function addSubstep(step) {
  step.substeps.push({ title: '', instruction: '' });
}
function removeSubstep(step, i) {
  step.substeps.splice(i, 1);
}
function addBranch(step) {
  step.branches.push({ condition: '', action: '' });
}
function removeBranch(step, i) {
  step.branches.splice(i, 1);
}

// ── Save ─────────────────────────────────────────────────────────────────────
async function save() {
  saving.value = true;
  error.value = null;
  saved.value = false;
  try {
    const res = await aiAgentsAPI.publishPrompt(props.agent.id, form.value);
    emit('updated', res.data.payload);
    saved.value = true;
    setTimeout(() => {
      saved.value = false;
    }, 3000);
  } catch {
    error.value = 'Erro ao salvar prompt.';
  } finally {
    saving.value = false;
  }
}

const inputClass =
  'w-full text-xs px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-violet-500/30';
const textareaClass = inputClass + ' resize-none';
const sectionClass =
  'bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl p-5 space-y-4';
const labelClass =
  'text-xs font-semibold text-slate-500 dark:text-slate-400 mb-1.5 block';
const addBtnClass =
  'text-[11px] text-violet-500 hover:underline flex items-center gap-1';
const removeBtnClass =
  'p-1 text-slate-300 hover:text-red-400 transition-colors shrink-0';
</script>

<template>
  <div class="space-y-5">
    <!-- Save bar -->
    <div class="flex items-center justify-between">
      <div>
        <p class="text-xs text-slate-400">
          Versão atual do prompt:
          <strong class="text-slate-600 dark:text-slate-300"
            >v{{ agent.prompt_version }}</strong
          >
        </p>
      </div>
      <div class="flex items-center gap-2">
        <span
          v-if="saved"
          class="text-xs text-emerald-500 flex items-center gap-1"
        >
          <span class="i-lucide-check size-3.5" /> Salvo como v{{
            agent.prompt_version
          }}
        </span>
        <span v-if="error" class="text-xs text-red-500">{{ error }}</span>
        <button
          class="flex items-center gap-1.5 px-4 py-2 text-xs font-semibold bg-violet-600 hover:bg-violet-700 text-white rounded-lg transition-colors disabled:opacity-50"
          :disabled="saving"
          @click="save"
        >
          <span v-if="saving" class="i-lucide-loader-2 size-3.5 animate-spin" />
          <span v-else class="i-lucide-save size-3.5" />
          {{ saving ? 'Salvando...' : 'Publicar prompt' }}
        </button>
      </div>
    </div>

    <!-- Identidade -->
    <div :class="sectionClass">
      <h3
        class="text-sm font-semibold text-slate-700 dark:text-slate-200 flex items-center gap-2"
      >
        <span class="i-lucide-user size-4 text-violet-500" /> Identidade
      </h3>
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label :class="labelClass">Nome do agente</label>
          <input
            v-model="form.name"
            type="text"
            placeholder="Sofia"
            :class="inputClass"
          />
        </div>
        <div>
          <label :class="labelClass">Empresa</label>
          <input
            v-model="form.company"
            type="text"
            placeholder="Volponi Advogados"
            :class="inputClass"
          />
        </div>
      </div>

      <!-- Objetivos -->
      <div>
        <label :class="labelClass">Objetivos</label>
        <div
          v-for="(obj, i) in form.objectives"
          :key="i"
          class="flex gap-2 mb-2 items-center"
        >
          <input
            v-model="form.objectives[i]"
            type="text"
            placeholder="Ex: Qualificar leads"
            :class="inputClass"
          />
          <button
            :class="removeBtnClass"
            @click="removeItem(form.objectives, i)"
          >
            <span class="i-lucide-x size-3.5" />
          </button>
        </div>
        <button :class="addBtnClass" @click="addItem(form.objectives)">
          <span class="i-lucide-plus size-3" /> Adicionar objetivo
        </button>
      </div>
    </div>

    <!-- Negócio -->
    <div :class="sectionClass">
      <h3
        class="text-sm font-semibold text-slate-700 dark:text-slate-200 flex items-center gap-2"
      >
        <span class="i-lucide-building-2 size-4 text-violet-500" /> Negócio
      </h3>
      <div>
        <label :class="labelClass">Nome da empresa</label>
        <input
          v-model="form.business.name"
          type="text"
          placeholder="Nome completo da empresa"
          :class="inputClass"
        />
      </div>
      <div>
        <label :class="labelClass">Descrição</label>
        <textarea
          v-model="form.business.description"
          rows="3"
          placeholder="O que a empresa faz..."
          :class="textareaClass"
        />
      </div>
      <div>
        <label :class="labelClass">Público-alvo</label>
        <input
          v-model="form.business.target_audience"
          type="text"
          placeholder="Ex: Pequenas e médias empresas"
          :class="inputClass"
        />
      </div>
    </div>

    <!-- Produtos -->
    <div :class="sectionClass">
      <div class="flex items-center justify-between">
        <h3
          class="text-sm font-semibold text-slate-700 dark:text-slate-200 flex items-center gap-2"
        >
          <span class="i-lucide-package size-4 text-violet-500" /> Produtos /
          Serviços
        </h3>
        <button :class="addBtnClass" @click="addProduct">
          <span class="i-lucide-plus size-3" /> Adicionar
        </button>
      </div>
      <div
        v-for="(product, i) in form.products"
        :key="i"
        class="border border-slate-100 dark:border-slate-700 rounded-lg p-3 space-y-2 relative"
      >
        <button
          class="absolute top-2 right-2"
          :class="[removeBtnClass]"
          @click="removeProduct(i)"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label :class="labelClass">Nome</label>
            <input
              v-model="product.name"
              type="text"
              placeholder="Nome do produto"
              :class="inputClass"
            />
          </div>
          <div>
            <label :class="labelClass">Valor</label>
            <input
              v-model="product.value"
              type="text"
              placeholder="Ex: R$ 497/mês"
              :class="inputClass"
            />
          </div>
        </div>
        <div>
          <label :class="labelClass">Descrição</label>
          <textarea
            v-model="product.description"
            rows="2"
            placeholder="O que inclui..."
            :class="textareaClass"
          />
        </div>
        <div>
          <label :class="labelClass">Público-alvo</label>
          <input
            v-model="product.target_audience"
            type="text"
            placeholder="Para quem é"
            :class="inputClass"
          />
        </div>
      </div>
      <p v-if="!form.products.length" class="text-xs text-slate-400 italic">
        Nenhum produto adicionado
      </p>
    </div>

    <!-- Personalidade -->
    <div :class="sectionClass">
      <h3
        class="text-sm font-semibold text-slate-700 dark:text-slate-200 flex items-center gap-2"
      >
        <span class="i-lucide-sparkles size-4 text-violet-500" /> Personalidade
      </h3>
      <div
        v-for="(p, i) in form.personality"
        :key="i"
        class="flex gap-2 mb-2 items-center"
      >
        <input
          v-model="form.personality[i]"
          type="text"
          placeholder="Ex: Empática e objetiva"
          :class="inputClass"
        />
        <button
          :class="removeBtnClass"
          @click="removeItem(form.personality, i)"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
      <button :class="addBtnClass" @click="addItem(form.personality)">
        <span class="i-lucide-plus size-3" /> Adicionar traço
      </button>
    </div>

    <!-- Regras -->
    <div :class="sectionClass">
      <h3
        class="text-sm font-semibold text-slate-700 dark:text-slate-200 flex items-center gap-2"
      >
        <span class="i-lucide-shield size-4 text-violet-500" /> Regras Gerais
      </h3>
      <div
        v-for="(r, i) in form.rules"
        :key="i"
        class="flex gap-2 mb-2 items-start"
      >
        <textarea
          v-model="form.rules[i]"
          rows="2"
          placeholder="Ex: Nunca mencionar concorrentes"
          :class="textareaClass"
        />
        <button
          class="mt-1"
          :class="[removeBtnClass]"
          @click="removeItem(form.rules, i)"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
      <button :class="addBtnClass" @click="addItem(form.rules)">
        <span class="i-lucide-plus size-3" /> Adicionar regra
      </button>
    </div>

    <!-- Fluxo de conversão -->
    <div :class="sectionClass">
      <div class="flex items-center justify-between">
        <h3
          class="text-sm font-semibold text-slate-700 dark:text-slate-200 flex items-center gap-2"
        >
          <span class="i-lucide-git-branch size-4 text-violet-500" /> Fluxo de
          Conversão
        </h3>
        <button :class="addBtnClass" @click="addStep">
          <span class="i-lucide-plus size-3" /> Adicionar etapa
        </button>
      </div>

      <div
        v-for="(step, si) in form.flow"
        :key="si"
        class="border border-slate-200 dark:border-slate-700 rounded-xl p-4 space-y-3"
      >
        <div class="flex items-center justify-between">
          <span class="text-xs font-bold text-violet-500"
            >Etapa {{ si + 1 }}</span
          >
          <button :class="removeBtnClass" @click="removeStep(si)">
            <span class="i-lucide-trash-2 size-3.5" />
          </button>
        </div>

        <div>
          <label :class="labelClass">Título</label>
          <input
            v-model="step.title"
            type="text"
            placeholder="Ex: Identificar interesse"
            :class="inputClass"
          />
        </div>
        <div>
          <label :class="labelClass">Instrução</label>
          <textarea
            v-model="step.instruction"
            rows="3"
            placeholder="O que o agente deve fazer nesta etapa..."
            :class="textareaClass"
          />
        </div>
        <div>
          <label :class="labelClass">Exemplo de mensagem</label>
          <textarea
            v-model="step.example"
            rows="2"
            placeholder="Ex: Olá! Vi que você tem interesse em..."
            :class="textareaClass"
          />
        </div>

        <!-- Subetapas -->
        <div
          class="pl-3 border-l-2 border-violet-100 dark:border-violet-900 space-y-2"
        >
          <div class="flex items-center justify-between">
            <span class="text-[11px] font-semibold text-slate-400"
              >Subetapas</span
            >
            <button :class="addBtnClass" @click="addSubstep(step)">
              <span class="i-lucide-plus size-3" /> Adicionar
            </button>
          </div>
          <div
            v-for="(sub, ssi) in step.substeps"
            :key="ssi"
            class="flex gap-2 items-start"
          >
            <div class="flex-1 space-y-1.5">
              <input
                v-model="sub.title"
                type="text"
                placeholder="Título da subetapa"
                :class="inputClass"
              />
              <textarea
                v-model="sub.instruction"
                rows="2"
                placeholder="Instrução..."
                :class="textareaClass"
              />
            </div>
            <button
              class="mt-1"
              :class="[removeBtnClass]"
              @click="removeSubstep(step, ssi)"
            >
              <span class="i-lucide-x size-3.5" />
            </button>
          </div>
        </div>

        <!-- Ramos -->
        <div
          class="pl-3 border-l-2 border-amber-100 dark:border-amber-900 space-y-2"
        >
          <div class="flex items-center justify-between">
            <span class="text-[11px] font-semibold text-slate-400"
              >Ramos condicionais</span
            >
            <button :class="addBtnClass" @click="addBranch(step)">
              <span class="i-lucide-plus size-3" /> Adicionar
            </button>
          </div>
          <div
            v-for="(branch, bi) in step.branches"
            :key="bi"
            class="flex gap-2 items-start"
          >
            <div class="flex-1 space-y-1.5">
              <input
                v-model="branch.condition"
                type="text"
                placeholder="Se..."
                :class="inputClass"
              />
              <input
                v-model="branch.action"
                type="text"
                placeholder="Então..."
                :class="inputClass"
              />
            </div>
            <button
              class="mt-1"
              :class="[removeBtnClass]"
              @click="removeBranch(step, bi)"
            >
              <span class="i-lucide-x size-3.5" />
            </button>
          </div>
        </div>
      </div>
      <p v-if="!form.flow.length" class="text-xs text-slate-400 italic">
        Nenhuma etapa de conversão definida
      </p>
    </div>

    <!-- Save bottom -->
    <div class="flex justify-end pt-2">
      <button
        class="flex items-center gap-1.5 px-4 py-2 text-xs font-semibold bg-violet-600 hover:bg-violet-700 text-white rounded-lg transition-colors disabled:opacity-50"
        :disabled="saving"
        @click="save"
      >
        <span v-if="saving" class="i-lucide-loader-2 size-3.5 animate-spin" />
        <span v-else class="i-lucide-save size-3.5" />
        {{ saving ? 'Salvando...' : 'Publicar prompt' }}
      </button>
    </div>
  </div>
</template>
