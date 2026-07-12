<script setup lang="ts">
import { Line } from "vue-chartjs";

interface RatingRow {
  fideid: number;
  period: string;
  rating_type: string;
  name: string;
  country: string | null;
  title: string | null;
  rating: number | null;
  games: number | null;
}

const { get } = useApi();

const { data: top } = await useAsyncData("top-standard", () =>
  get<RatingRow[]>("/latest_ratings", {
    rating_type: "eq.standard",
    order: "rating.desc",
    limit: "25",
  }),
);

const rows = computed(() =>
  (top.value ?? []).map((r, i) => ({ ...r, rank: i + 1 })),
);

const topIds = computed(() => (top.value ?? []).slice(0, 5).map((r) => r.fideid));

const { data: history } = await useAsyncData(
  "history-top5",
  () =>
    topIds.value.length
      ? get<RatingRow[]>("/ratings", {
          fideid: `in.(${topIds.value.join(",")})`,
          rating_type: "eq.standard",
          order: "period.asc",
          select: "fideid,period,rating,name",
        })
      : Promise.resolve([] as RatingRow[]),
  { watch: [topIds] },
);

const headers = [
  { title: "#", key: "rank", width: 60 },
  { title: "Name", key: "name" },
  { title: "Country", key: "country" },
  { title: "Title", key: "title" },
  { title: "Rating", key: "rating" },
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
          <v-data-table :headers="headers" :items="rows" :items-per-page="25" density="compact" />
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
