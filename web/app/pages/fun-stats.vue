<script setup lang="ts">
import { ref, computed } from "vue";
import { useAsyncData } from "#app";
import { useI18n, useLocalePath } from "#i18n";
import type { EloThresholdStat } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useRatingTypeOptions } from "~/composables/useFilterOptions";
import { useUrlFilters } from "~/composables/useUrlFilters";
import { ELO_THRESHOLD_OPTIONS } from "~/utils/filterOptions";

const { get } = useApi();
const { t, locale } = useI18n();
const localePath = useLocalePath();

const { countryName, countryFlag } = await useCountryOptions();
const ratingTypeOptions = useRatingTypeOptions(false);

const threshold = ref<number>(2500);
const ratingType = ref<string>("standard");

useUrlFilters({ threshold, ratingType });

const { data, pending } = await useAsyncData<EloThresholdStat[]>(
  "elo-threshold-stats",
  (_nuxtApp, { signal }) =>
    get<EloThresholdStat[]>("/rpc/elo_threshold_stats", {
      p_threshold: String(threshold.value),
      p_rating_type: ratingType.value,
    }, { signal }),
  { watch: [threshold, ratingType] },
);

const cards = computed(() => {
  const byMetric = new Map((data.value ?? []).map((r) => [r.metric, r]));
  return [
    { metric: "youngest" as const, titleKey: "pages.funStatsYoungest", icon: "mdi-emoticon-cool-outline", row: byMetric.get("youngest") },
    { metric: "oldest" as const, titleKey: "pages.funStatsOldest", icon: "mdi-account-clock-outline", row: byMetric.get("oldest") },
    { metric: "fewest_games" as const, titleKey: "pages.funStatsFewestGames", icon: "mdi-rocket-launch-outline", row: byMetric.get("fewest_games") },
  ];
});

function formatPeriod(period: string) {
  return new Intl.DateTimeFormat(locale.value, { year: "numeric", month: "long" }).format(new Date(period));
}
</script>

<template>
  <v-container fluid>
    <v-card :title="t('nav.funStats')">
      <v-card-text class="d-flex flex-wrap" style="gap: 16px">
        <v-select
          v-model="threshold"
          :items="ELO_THRESHOLD_OPTIONS"
          :label="t('filters.eloThreshold')"
          density="compact"
          hide-details
          style="max-width: 160px"
        />
        <v-select
          v-model="ratingType"
          :items="ratingTypeOptions"
          :label="t('filters.timeControl')"
          density="compact"
          hide-details
          style="max-width: 200px"
        />
      </v-card-text>
    </v-card>
    <div class="d-flex flex-wrap align-stretch mt-4" style="gap: 16px">
      <v-card v-for="c in cards" :key="c.metric" class="flex-grow-1" style="min-width: 260px">
        <v-card-item>
          <template #prepend><v-icon :icon="c.icon" /></template>
          <v-card-title>{{ t(c.titleKey, { elo: threshold }) }}</v-card-title>
        </v-card-item>
        <v-card-text v-if="pending">
          <v-progress-circular indeterminate size="24" />
        </v-card-text>
        <v-card-text v-else-if="c.row">
          <div class="d-flex align-center" style="gap: 8px">
            <span
              v-if="countryFlag(c.row.country)"
              :class="countryFlag(c.row.country)"
              :title="countryName(c.row.country)"
              style="font-size: 1.3em"
            />
            <span v-if="c.row.title" class="player-title-prefix">{{ c.row.title }}</span>
            <NuxtLink :to="localePath(`/player/${c.row.fideid}`)" class="player-name-link text-high-emphasis text-h6">
              {{ c.row.name }}
            </NuxtLink>
          </div>
          <div class="text-medium-emphasis mt-1">{{ t("pages.ageYears", { n: c.row.age }) }}</div>
          <div class="text-medium-emphasis">{{ t("pages.funStatsReachedOn", { elo: c.row.rating, period: formatPeriod(c.row.period) }) }}</div>
          <div class="text-medium-emphasis">{{ t("pages.funStatsGamesCount", { n: c.row.games_to_threshold }) }}</div>
        </v-card-text>
      </v-card>
    </div>
  </v-container>
</template>

<style scoped>
.player-title-prefix {
  color: #ff8f00;
  font-weight: 700;
  font-size: 0.85em;
}
.player-name-link {
  color: rgb(var(--v-theme-primary));
  text-decoration: underline;
  text-decoration-color: transparent;
  transition: text-decoration-color 0.15s;
}
.player-name-link:hover {
  text-decoration-color: currentColor;
}
</style>
