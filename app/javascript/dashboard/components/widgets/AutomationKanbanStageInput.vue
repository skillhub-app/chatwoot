<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

const props = defineProps({
  modelValue: {
    type: [Array, null],
    default: null,
  },
  pipelines: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const store = useStore();
const getters = useStoreGetters();
const selectedPipelineId = ref(null);
const stagesLoading = ref(false);

const stagesForPipeline = computed(() => {
  if (!selectedPipelineId.value) return [];
  return getters['kanban/getPipelineStagesCache']
    .value(selectedPipelineId.value)
    .map(s => ({
      id: s.id,
      name: s.name,
    }));
});

const pipelineOptions = computed(() =>
  props.pipelines.map(p => ({ id: p.id, name: p.name }))
);

const selectedPipelineOption = computed({
  get: () =>
    pipelineOptions.value.find(p => p.id === selectedPipelineId.value) || null,
  set: async val => {
    selectedPipelineId.value = val?.id || null;
    emit('update:modelValue', []);
    if (selectedPipelineId.value) {
      stagesLoading.value = true;
      await store.dispatch(
        'kanban/fetchPipelineStages',
        selectedPipelineId.value
      );
      stagesLoading.value = false;
    }
  },
});

const selectedStageOption = computed({
  get: () => {
    const stageId = Array.isArray(props.modelValue)
      ? props.modelValue[0]
      : null;
    if (!stageId) return null;
    return stagesForPipeline.value.find(s => s.id === stageId) || null;
  },
  set: val => {
    emit('update:modelValue', val ? [val.id] : []);
  },
});

// On mount: if modelValue already has a stage_id, find which pipeline owns it
onMounted(async () => {
  const stageId = Array.isArray(props.modelValue) ? props.modelValue[0] : null;
  if (!stageId || !props.pipelines.length) return;

  await Promise.all(
    props.pipelines.map(p => store.dispatch('kanban/fetchPipelineStages', p.id))
  );

  const owning = props.pipelines.find(p =>
    getters['kanban/getPipelineStagesCache']
      .value(p.id)
      .some(s => s.id === stageId)
  );
  if (owning) selectedPipelineId.value = owning.id;
});

// Reset stage when pipeline changes externally
watch(selectedPipelineId, () => {
  const stageId = Array.isArray(props.modelValue) ? props.modelValue[0] : null;
  if (!stageId) return;
  const valid = stagesForPipeline.value.find(s => s.id === stageId);
  if (!valid) emit('update:modelValue', []);
});
</script>

<template>
  <div class="flex gap-2 flex-1 min-w-0">
    <SingleSelect
      v-model="selectedPipelineOption"
      :options="pipelineOptions"
      :placeholder="$t('AUTOMATION.ACTION.KANBAN_PIPELINE_PLACEHOLDER')"
      class="flex-1 min-w-0"
    />
    <SingleSelect
      v-model="selectedStageOption"
      :options="stagesForPipeline"
      :placeholder="$t('AUTOMATION.ACTION.KANBAN_STAGE_PLACEHOLDER')"
      class="flex-1 min-w-0"
    />
  </div>
</template>
