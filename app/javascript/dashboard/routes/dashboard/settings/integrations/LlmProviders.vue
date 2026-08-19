<script setup>
import { useRouter } from 'vue-router';
import LlmProvidersConfigModal from 'dashboard/components/aiAgent/LlmProvidersConfigModal.vue';

const router = useRouter();

function close() {
  router.push({ name: 'settings_applications' });
}
</script>

<template>
  <LlmProvidersConfigModal show @close="close" />
</template>
