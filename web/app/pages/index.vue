<script setup lang="ts">
import { Line } from "vue-chartjs";
import type { LatestRating, Rating } from "~/types/api";

const { get } = useApi();

const { data: top } = await useAsyncData("top-standard", () =>
  get<LatestRating[]>("/latest_ratings", {
    rating_type: "eq.standard",
    or: "(flag.is.null,flag.not.in.(i,wi))",
    order: "rating.desc",
    limit: "25",
  }),
);

const currentYear = new Date().getFullYear();
const rows = computed(() =>
  (top.value ?? []).map((r, i) => ({
    ...r,
    rank: i + 1,
    age: r.birthday ? currentYear - r.birthday : null,
  })),
);

const topIds = computed(() => (top.value ?? []).slice(0, 5).map((r) => r.fideid));

const { data: history } = await useAsyncData(
  "history-top5",
  () =>
    topIds.value.length
      ? get<Rating[]>("/ratings", {
          fideid: `in.(${topIds.value.join(",")})`,
          rating_type: "eq.standard",
          order: "period.asc",
          select: "fideid,period,rating,name",
        })
      : Promise.resolve([] as Rating[]),
  { watch: [topIds] },
);

const headers = [
  { title: "#", key: "rank", width: 60 },
  { title: "Name", key: "name" },
  { title: "Country", key: "country" },
  { title: "Title", key: "title" },
  { title: "Rating", key: "rating" },
  { title: "Age", key: "age" },
  { title: "Games", key: "games" },
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
    <v-row>
      <v-col cols="12" md="6">
        <v-card title="Top 25 — Standard rating">
          <v-data-table :headers="headers" :items="rows" :items-per-page="25" density="compact">
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
