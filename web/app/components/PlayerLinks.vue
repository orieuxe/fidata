<script setup lang="ts">
import { useI18n } from "#i18n";
import { fideProfileUrl, grandRoqueUrl, lichessUrl } from "~/utils/links";

const { fideid, name, size = 14, showProfileLink = false } = defineProps<{
  fideid: number;
  name: string;
  size?: number;
  showProfileLink?: boolean;
}>();

const { t } = useI18n();
</script>

<template>
  <a :href="fideProfileUrl(fideid)" target="_blank" rel="noopener" :title="t('links.fideProfile')">
    <img src="/icons/fide.png" :width="size" :height="size" alt="FIDE" />
  </a>
  <a :href="lichessUrl(fideid, name)" target="_blank" rel="noopener" :title="t('links.lichess')">
    <img src="/icons/lichess.png" :width="size" :height="size" alt="Lichess" />
  </a>
  <a :href="grandRoqueUrl(fideid)" target="_blank" rel="noopener" :title="t('links.grandRoque')">
    <img src="/icons/grandroque.svg" :width="size" :height="size" alt="Grand Roque" />
  </a>
  <NuxtLink v-if="showProfileLink" :to="`/player/${fideid}`" :title="t('links.playerProfile')">
    <v-icon :size="size" icon="mdi-chart-line" />
  </NuxtLink>
</template>
