<script setup lang="ts">
import { ref, computed } from "vue";
import { useAsyncData } from "#app";
import { useI18n } from "#i18n";
import { Line } from "vue-chartjs";
import type { TopPlayer, Rating } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useYearOptions, useRatingTypeOptions, useBaseHeaders } from "~/composables/useFilterOptions";
import { TITLE_OPTIONS, LIMIT_OPTIONS_WIDE } from "~/utils/filterOptions";

const { get } = useApi();
const { t } = useI18n();

const { currentYear, yearOptions } = useYearOptions(false);
const { countryOptions, countryName, countryFlag } = await useCountryOptions();
const ratingTypeOptions = useRatingTypeOptions(false);

const titleOptions = TITLE_OPTIONS;
const limitOptions = LIMIT_OPTIONS_WIDE;

const year = ref<number>(currentYear);
const country = ref<string | null>(null);
const ratingType = ref<string>("standard");
const titles = ref<string[]>([]);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);
const limit = ref<number>(10);

const { data: top, pending } = await useAsyncData<TopPlayer[]>(
  "top-players",
  (_nuxtApp, { signal }) =>
    get<TopPlayer[]>("/rpc/top_players", {
      p_year: String(year.value),
      ...(country.value && { p_country: country.value }),
      p_rating_type: ratingType.value,
      ...(titles.value.length && { p_titles: `{${titles.value.join(",")}}` }),
      ...(minAge.value != null && { p_min_age: String(minAge.value) }),
      ...(maxAge.value != null && { p_max_age: String(maxAge.value) }),
      p_limit: String(limit.value),
    }, { signal }),
  { watch: [year, country, ratingType, titles, minAge, maxAge, limit] },
);

const rows = computed(() => (top.value ?? []).map((r, i) => ({ ...r, rank: i + 1 })));

const topIds = computed(() => (top.value ?? []).slice(0, 15).map((r) => r.fideid));

const { data: history, pending: historyPending } = await useAsyncData(
  "rating-history",
  (_nuxtApp, { signal }) =>
    topIds.value.length
      ? get<Rating[]>("/ratings", {
          fideid: `in.(${topIds.value.join(",")})`,
          rating_type: `eq.${ratingType.value}`,
          period: `lte.${year.value}-12-31`,
          order: "period.asc",
          select: "fideid,period,rating,name",
        }, { signal })
      : Promise.resolve([] as Rating[]),
  { watch: [topIds, ratingType, year, country, titles, minAge, maxAge, limit] },
);

const baseHeaders = useBaseHeaders();
const headers = computed(() => [
  ...baseHeaders.value,
  { title: t("table.rating"), key: "rating" },
  { title: t("table.age"), key: "age" },
]);

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

const chartOptions = { responsive: true, plugins: { legend: { position: "bottom" as const } } };
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
        <v-row dense>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="year" :items="yearOptions" :label="t('filters.year')" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-autocomplete v-model="country" :items="countryOptions" :label="t('filters.country')" density="compact">
              <template #item="{ props, item }">
                <v-list-item v-bind="props" title="">
                  <span v-if="countryFlag(item.raw?.value)" :class="countryFlag(item.raw?.value)" class="mr-2" />
                  {{ item.raw?.title ?? item.title }}
                </v-list-item>
              </template>
              <template #selection="{ item }">
                <span v-if="countryFlag(item.raw?.value)" :class="countryFlag(item.raw?.value)" class="mr-2" />
                {{ item.raw?.title ?? item.title }}
              </template>
            </v-autocomplete>
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="ratingType" :items="ratingTypeOptions" :label="t('filters.timeControl')" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="titles" :items="titleOptions" :label="t('filters.title')" multiple chips density="compact" />
          </v-col>
          <v-col cols="6" md="1">
            <v-text-field v-model.number="minAge" type="number" :label="t('filters.minAge')" density="compact" />
          </v-col>
          <v-col cols="6" md="1">
            <v-text-field v-model.number="maxAge" type="number" :label="t('filters.maxAge')" density="compact" />
          </v-col>
        </v-row>
      </v-card-text>
    </v-card>
    <v-card class="mb-4">
      <v-data-table :headers="headers" :items="rows" :loading="pending" :items-per-page="-1" hide-default-footer density="compact">
        <template #item.name="{ item }">
          <div class="d-flex align-center" style="gap: 6px">
            <PlayerLinks :fideid="item.fideid" :name="item.name" show-profile-link />
            <span>{{ item.name }}</span>
          </div>
        </template>
        <template #item.country="{ item }">
          <span
            v-if="countryFlag(item.country)"
            :class="countryFlag(item.country)"
            :title="countryName(item.country)"
            style="font-size: 1.2em"
          />
          <span v-else :title="item.country">{{ item.country }}</span>
        </template>
      </v-data-table>
    </v-card>
    <v-card>
      <div class="pa-4">
        <Line v-if="!historyPending && chartData.labels.length" :data="chartData" :options="chartOptions" />
        <p v-else class="text-medium-emphasis">{{ t("pages.loadingHistory") }}</p>
      </div>
    </v-card>
  </v-container>
</template>
