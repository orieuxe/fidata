<script setup lang="ts">
import { ref, computed, watch } from "vue";
import { useI18n } from "#i18n";
import { useDisplay } from "vuetify";
import { Line } from "vue-chartjs";
import type { TopPlayer, Rating } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useYearOptions, useRatingTypeOptions, useBaseHeaders, useTitleOptions, useSexOptions } from "~/composables/useFilterOptions";
import { useUrlFilters } from "~/composables/useUrlFilters";
import { useSequenceGuard } from "~/composables/useSequenceGuard";
import { LIMIT_OPTIONS_WIDE, buildBaseFilterParams } from "~/utils/filterOptions";
import FilterBar from "~/components/FilterBar.vue";
import PlayerTable from "~/components/PlayerTable.vue";

const { get } = useApi();
const { t } = useI18n();
const { xs } = useDisplay();

const { currentYear, yearOptions } = useYearOptions(false);
const { countryOptions, countryName, countryFlag } = await useCountryOptions();
const ratingTypeOptions = useRatingTypeOptions(false);

const titleOptions = useTitleOptions();
const sexOptions = useSexOptions();
const limitOptions = LIMIT_OPTIONS_WIDE;

const year = ref<number>(currentYear);
const country = ref<string | null>(null);
const ratingType = ref<string>("standard");
const titles = ref<string[]>([]);
const sex = ref<string | null>(null);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);
const limit = ref<number>(10);

useUrlFilters({ year, country, ratingType, titles, sex, minAge, maxAge, limit });

const top = ref<TopPlayer[]>([]);
const history = ref<Rating[]>([]);
const pending = ref(false);
const historyPending = ref(false);

const { start, isStale } = useSequenceGuard();

async function load() {
  const token = start();
  pending.value = true;
  historyPending.value = true;

  const topData = await get<TopPlayer[]>("/rpc/top_players", {
    p_year: String(year.value),
    ...buildBaseFilterParams({ country, sex, ratingType, titles, minAge, maxAge }),
    p_limit: String(limit.value),
  });
  if (isStale(token)) return;
  top.value = topData;
  pending.value = false;

  const topIds = topData.slice(0, 15).map((r) => r.fideid);
  const historyData = topIds.length
    ? await get<Rating[]>("/ratings", {
        fideid: `in.(${topIds.join(",")})`,
        rating_type: `eq.${ratingType.value}`,
        period: `lte.${year.value}-12-31`,
        order: "period.asc",
        select: "fideid,period,rating,name",
      })
    : [];
  if (isStale(token)) return;
  history.value = historyData;
  historyPending.value = false;
}

watch([year, country, ratingType, titles, sex, minAge, maxAge, limit], load);
await load();

const rows = computed(() => top.value.map((r, i) => ({ ...r, rank: i + 1 })));

// Local header reorder: flag before name; no rank/title column on mobile (title renders inline in #item.name).
const baseHeaders = useBaseHeaders();
const headers = computed(() => {
  const base = baseHeaders.value;
  const byKey = (key: string) => base.find((h) => h.key === key)!;
  return [
    ...(xs.value ? [] : [{ title: t("table.rank"), key: "rank", width: 50 }]),
    { ...byKey("country"), width: xs.value ? 36 : 50 },
    byKey("name"),
    { title: t("table.rating"), key: "rating", width: xs.value ? 56 : 100 },
    { title: t("table.age"), key: "age", width: xs.value ? 48 : 80 },
  ];
});

const chartData = computed(() => {
  const rows = history.value ?? [];
  const labels = [...new Set(rows.map((r) => r.period))].sort();
  const byPlayer = new Map<number, { name: string; byPeriod: Map<string, number> }>();
  for (const r of rows) {
    if (!byPlayer.has(r.fideid)) byPlayer.set(r.fideid, { name: r.name, byPeriod: new Map() });
    byPlayer.get(r.fideid)!.byPeriod.set(r.period, r.rating ?? NaN);
  }
  const colors = [
    "#e57373", "#64b5f6", "#81c784", "#ffd54f", "#ba68c8",
    "#4db6ac", "#f06292", "#a1887f", "#90a4ae", "#dce775",
  ];
  const datasets = [...byPlayer.values()].map((p, i) => ({
    label: p.name,
    data: labels.map((period) => p.byPeriod.get(period) ?? null),
    borderColor: colors[i % colors.length],
    spanGaps: true,
  }));
  return { labels, datasets };
});

const chartOptions = { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: "bottom" as const } } };
</script>

<template>
  <v-container fluid>
    <v-card class="mb-4">
      <v-card-title class="d-flex flex-wrap align-center" style="gap: 12px">
        <span>{{ t('pages.topPlayersCard') }}</span>
        <v-select
          v-model="limit"
          :items="limitOptions"
          :label="t('filters.limit')"
          density="compact"
          hide-details
          style="max-width: 130px"
        />
      </v-card-title>
      <v-card-text>
        <FilterBar
          v-model:year="year"
          v-model:country="country"
          v-model:rating-type="ratingType"
          v-model:titles="titles"
          v-model:sex="sex"
          v-model:min-age="minAge"
          v-model:max-age="maxAge"
          :year-options="yearOptions"
          :country-options="countryOptions"
          :country-flag="countryFlag"
          :rating-type-options="ratingTypeOptions"
          :title-options="titleOptions"
          :sex-options="sexOptions"
        />
      </v-card-text>
    </v-card>
    <div class="d-flex flex-wrap align-start" style="gap: 16px">
      <v-card style="width: 620px; max-width: 100%">
        <PlayerTable
          :headers="headers"
          :items="rows"
          :loading="pending"
          :country-flag="countryFlag"
          :country-name="countryName"
        />
      </v-card>
      <v-card class="flex-grow-1" style="min-width: 320px">
        <div class="pa-4" style="height: 420px">
          <Line v-if="!historyPending && chartData.labels.length" :data="chartData" :options="chartOptions" />
          <p v-else class="text-medium-emphasis">{{ t("pages.loadingHistory") }}</p>
        </div>
      </v-card>
    </div>
  </v-container>
</template>
