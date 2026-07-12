<script setup lang="ts">
import { Line } from "vue-chartjs";
import type { TopPlayer, Rating, Country } from "~/types/api";

const { get } = useApi();

const currentYear = new Date().getFullYear();
const years = Array.from({ length: currentYear - 2015 + 2 }, (_, i) => currentYear + 1 - i); // newest first, +1 = "All time"
const yearOptions = years.map((y) => (y > currentYear ? { title: "All time", value: null } : { title: String(y), value: y }));

const { data: countries } = await useAsyncData("countries", () =>
  get<Country[]>("/countries"),
);
const countryOptions = computed(() => [
  { title: "All countries", value: null },
  ...(countries.value ?? []).map((c) => ({ title: c.code, value: c.code })),
]);

const ratingTypeOptions = [
  { title: "Standard", value: "standard" },
  { title: "Rapid", value: "rapid" },
  { title: "Blitz", value: "blitz" },
];

const titleOptions = ["GM", "IM", "FM", "CM", "WGM", "WIM", "WFM", "WCM", "UNTITLED"];

const year = ref<number | null>(currentYear);
const country = ref<string | null>(null);
const ratingType = ref<string>("standard");
const titles = ref<string[]>([]);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);

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
      p_limit: "25",
    }),
  { watch: [year, country, ratingType, titles, minAge, maxAge] },
);

const rows = computed(() => (top.value ?? []).map((r, i) => ({ ...r, rank: i + 1 })));

const topIds = computed(() => (top.value ?? []).slice(0, 5).map((r) => r.fideid));

const { data: history } = await useAsyncData(
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
  { watch: [topIds, ratingType] },
);

const headers = [
  { title: "#", key: "rank", width: 60 },
  { title: "Name", key: "name" },
  { title: "Country", key: "country" },
  { title: "Title", key: "title" },
  { title: "Rating", key: "rating" },
  { title: "Age", key: "age" },
];

const chartData = computed(() => {
  const rows = history.value ?? [];
  const labels = [...new Set(rows.map((r) => r.period))].sort();
  const byPlayer = new Map<number, { name: string; byPeriod: Map<string, number> }>();
  for (const r of rows) {
    if (!byPlayer.has(r.fideid)) byPlayer.set(r.fideid, { name: r.name, byPeriod: new Map() });
    byPlayer.get(r.fideid)!.byPeriod.set(r.period, r.rating ?? NaN);
  }
  const colors = ["#e57373", "#64b5f6", "#81c784", "#ffd54f", "#ba68c8"];
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
    <v-card title="Top players" class="mb-4">
      <v-card-text>
        <v-row dense>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="year" :items="yearOptions" label="Year" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-autocomplete v-model="country" :items="countryOptions" label="Country" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="ratingType" :items="ratingTypeOptions" label="Time control" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="titles" :items="titleOptions" label="Title" multiple chips density="compact" />
          </v-col>
          <v-col cols="6" md="2">
            <v-text-field v-model.number="minAge" type="number" label="Min age" density="compact" />
          </v-col>
          <v-col cols="6" md="2">
            <v-text-field v-model.number="maxAge" type="number" label="Max age" density="compact" />
          </v-col>
        </v-row>
        <p v-if="year == null" class="text-caption text-medium-emphasis">
          "All time" scans the full rating history and can take a while.
        </p>
      </v-card-text>
    </v-card>
    <v-row>
      <v-col cols="12" md="6">
        <v-card title="Top 25">
          <v-data-table :headers="headers" :items="rows" :loading="pending" :items-per-page="25" density="compact">
            <template #item.name="{ item }">
              <div class="d-flex align-center" style="gap: 6px">
                <a :href="fideProfileUrl(item.fideid)" target="_blank" rel="noopener" title="FIDE profile">
                  <img src="/icons/fide.png" width="14" height="14" alt="FIDE" />
                </a>
                <a :href="lichessUrl(item.fideid, item.name)" target="_blank" rel="noopener" title="Lichess">
                  <img src="/icons/lichess.png" width="14" height="14" alt="Lichess" />
                </a>
                <span>{{ item.name }}</span>
              </div>
            </template>
          </v-data-table>
        </v-card>
      </v-col>
      <v-col cols="12" md="6">
        <v-card title="Rating history — top 5">
          <div class="pa-4">
            <Line v-if="chartData.labels.length" :data="chartData" :options="chartOptions" />
            <p v-else class="text-medium-emphasis">Loading history…</p>
          </div>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
