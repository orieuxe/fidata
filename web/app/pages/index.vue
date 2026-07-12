<script setup lang="ts">
import { Line } from "vue-chartjs";
import type { TopPlayer, Rating, Country } from "~/types/api";

const { get } = useApi();
const { t } = useI18n();

const currentYear = new Date().getFullYear();
const years = Array.from({ length: currentYear - 2015 + 2 }, (_, i) => currentYear + 1 - i); // newest first, +1 = "All time"
const yearOptions = years.map((y) => (y > currentYear ? { title: t("filters.allTime"), value: null } : { title: String(y), value: y }));

const { data: countries } = await useAsyncData("countries", () =>
  get<Country[]>("/countries"),
);
const countryOptions = computed(() => [
  { title: t("filters.allCountries"), value: null },
  ...(countries.value ?? []).map((c) => ({ title: c.code, value: c.code })),
]);

const ratingTypeOptions = computed(() => [
  { title: t("filters.standard"), value: "standard" },
  { title: t("filters.rapid"), value: "rapid" },
  { title: t("filters.blitz"), value: "blitz" },
]);

const titleOptions = ["GM", "IM", "FM", "CM", "WGM", "WIM", "WFM", "WCM", "UNTITLED"];
const limitOptions = [10, 25, 50, 100, 200];

const year = ref<number | null>(currentYear);
const country = ref<string | null>(null);
const ratingType = ref<string>("standard");
const titles = ref<string[]>([]);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);
const limit = ref<number>(10);

const { data: top, pending } = await useAsyncData<TopPlayer[]>(
  "top-players",
  () =>
    get<TopPlayer[]>("/rpc/top_players", {
      ...(year.value != null && { p_year: String(year.value) }),
      ...(country.value && { p_country: country.value }),
      p_rating_type: ratingType.value,
      ...(titles.value.length && { p_titles: `{${titles.value.join(",")}}` }),
      ...(minAge.value != null && { p_min_age: String(minAge.value) }),
      ...(maxAge.value != null && { p_max_age: String(maxAge.value) }),
      p_limit: String(limit.value),
    }),
  { watch: [year, country, ratingType, titles, minAge, maxAge, limit] },
);

const rows = computed(() => (top.value ?? []).map((r, i) => ({ ...r, rank: i + 1 })));

const topIds = computed(() => (top.value ?? []).slice(0, 10).map((r) => r.fideid));

const { data: history, pending: historyPending } = await useAsyncData(
  "history-top5",
  () =>
    topIds.value.length
      ? get<Rating[]>("/ratings", {
          fideid: `in.(${topIds.value.join(",")})`,
          rating_type: `eq.${ratingType.value}`,
          order: "period.asc",
          select: "fideid,period,rating,name",
        })
      : Promise.resolve([] as Rating[]),
  { watch: [topIds, ratingType, limit] },
);

const headers = computed(() => [
  { title: t("table.rank"), key: "rank", width: 60 },
  { title: t("table.name"), key: "name" },
  { title: t("table.country"), key: "country" },
  { title: t("table.title"), key: "title" },
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
    <v-card :title="t('pages.topPlayersCard')" class="mb-4">
      <v-card-text>
        <v-row dense>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="year" :items="yearOptions" :label="t('filters.year')" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-autocomplete v-model="country" :items="countryOptions" :label="t('filters.country')" density="compact" />
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
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="limit" :items="limitOptions" :label="t('filters.limit')" density="compact" />
          </v-col>
        </v-row>
        <p v-if="year == null" class="text-caption text-medium-emphasis">
          {{ t("pages.allTimeWarning") }}
        </p>
      </v-card-text>
    </v-card>
    <v-card :title="t('pages.top25', { n: limit })" class="mb-4">
      <v-data-table :headers="headers" :items="rows" :loading="pending" :items-per-page="-1" hide-default-footer density="compact">
        <template #item.name="{ item }">
          <div class="d-flex align-center" style="gap: 6px">
            <a :href="fideProfileUrl(item.fideid)" target="_blank" rel="noopener" :title="t('links.fideProfile')">
              <img src="/icons/fide.png" width="14" height="14" alt="FIDE" />
            </a>
            <a :href="lichessUrl(item.fideid, item.name)" target="_blank" rel="noopener" :title="t('links.lichess')">
              <img src="/icons/lichess.png" width="14" height="14" alt="Lichess" />
            </a>
            <span>{{ item.name }}</span>
          </div>
        </template>
      </v-data-table>
    </v-card>
    <v-card :title="t('pages.ratingHistory')">
      <div class="pa-4">
        <Line v-if="!historyPending && chartData.labels.length" :data="chartData" :options="chartOptions" />
        <p v-else class="text-medium-emphasis">{{ t("pages.loadingHistory") }}</p>
      </div>
    </v-card>
  </v-container>
</template>
