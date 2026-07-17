<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "#i18n";
import { fideProfileUrl, grandRoqueUrl, lichessUrl } from "~/utils/links";

const { fideid, name, size = 14, showProfileLink = false, detailed = false } = defineProps<{
  fideid: number;
  name: string;
  size?: number;
  showProfileLink?: boolean;
  detailed?: boolean;
}>();

const { t } = useI18n();

const links = computed(() => [
  { href: fideProfileUrl(fideid), icon: "/icons/fide.png", alt: "FIDE", title: t("links.fideProfile"), hint: t("links.fideProfileHint") },
  { href: lichessUrl(fideid, name), icon: "/icons/lichess.png", alt: "Lichess", title: t("links.lichess"), hint: t("links.lichessHint") },
  { href: grandRoqueUrl(fideid), icon: "/icons/grandroque.svg", alt: "Grand Roque", title: t("links.grandRoque"), hint: t("links.grandRoqueHint") },
]);
</script>

<template>
  <template v-if="detailed">
    <a
      v-for="l in links"
      :key="l.href"
      :href="l.href"
      target="_blank"
      rel="noopener"
      class="d-flex align-center text-decoration-none text-medium-emphasis"
      style="gap: 4px"
    >
      <img :src="l.icon" :width="size" :height="size" :alt="l.alt" />
      <span class="text-caption">{{ l.hint }}</span>
    </a>
  </template>
  <template v-else>
    <a v-for="l in links" :key="l.href" :href="l.href" target="_blank" rel="noopener" :title="l.hint">
      <img :src="l.icon" :width="size" :height="size" :alt="l.alt" />
    </a>
  </template>
  <NuxtLink v-if="showProfileLink" :to="`/player/${fideid}`" :title="t('links.playerProfile')">
    <v-icon :size="size" icon="mdi-chart-line" />
  </NuxtLink>
</template>
