<script setup lang="ts">
import { computed } from "vue";
import { useAsyncData, useRoute } from "#app";
import { useI18n } from "#i18n";
import { Line } from "vue-chartjs";
import type { PlayerProfile, PlayerYearlyStat, Rating } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions } from "~/composables/useFilterOptions";
import { fideProfileUrl, lichessUrl } from "~/utils/links";

const route = useRoute();
const { get } = useApi();
const { t } = useI18n();
const { countryName, countryFlag } = await useCountryOptions();

const fideid = computed(() => Number(route.params.fideid));

const { data: profileRows } = await useAsyncData(
  () => `player-profile-${fideid.value}`,
  (_nuxtApp, { signal }) =>
    get<PlayerProfile[]>("/rpc/player_profile", { p_fideid: String(fideid.value) }, { signal }),
  { watch: [fideid] },
);
const player = computed(() => profileRows.value?.[0] ?? null);

const { data: history, pending: historyPending } = await useAsyncData(
  () => `player-history-${fideid.value}`,
  (_nuxtApp, { signal }) =>
    get<Rating[]>("/ratings", {
      fideid: `eq.${fideid.value}`,
      order: "period.asc",
      select: "period,rating,rating_type",
    }, { signal }),
  { watch: [fideid] },
);

const { data: yearlyStats } = await useAsyncData(
  () => `player-yearly-${fideid.value}`,
  (_nuxtApp, { signal }) =>
    get<PlayerYearlyStat[]>("/rpc/player_yearly_stats", { p_fideid: String(fideid.value) }, { signal }),
  { watch: [fideid] },
);

const CADENCE_COLORS = { standard: "#64b5f6", rapid: "#81c784", blitz: "#ffd54f" } as const;

const cadenceRows = computed(() => {
  if (!player.value) return [];
  const p = player.value;
  return [
    { key: "standard", label: t("filters.standard"), rating: p.rating_standard, max: p.max_standard },
    { key: "rapid", label: t("filters.rapid"), rating: p.rating_rapid, max: p.max_rapid },
    { key: "blitz", label: t("filters.blitz"), rating: p.rating_blitz, max: p.max_blitz },
  ];
});

const chartData = computed(() => {
  const rows = history.value ?? [];
  const labels = [...new Set(rows.map((r) => r.period))].sort();
  const byType = new Map<string, Map<string, number>>();
  for (const r of rows) {
    if (!byType.has(r.rating_type)) byType.set(r.rating_type, new Map());
    byType.get(r.rating_type)!.set(r.period, r.rating ?? NaN);
  }
  const datasets = (Object.keys(CADENCE_COLORS) as (keyof typeof CADENCE_COLORS)[])
    .filter((type) => byType.has(type))
    .map((type) => ({
      label: t(`filters.${type}`),
      data: labels.map((period) => byType.get(type)!.get(period) ?? null),
      borderColor: CADENCE_COLORS[type],
      spanGaps: true,
    }));
  return { labels, datasets };
});

const chartOptions = { responsive: true, plugins: { legend: { position: "bottom" as const } } };

function fmtDelta(delta: number | null) {
  if (delta == null) return "";
  return delta > 0 ? `+${delta}` : `${delta}`;
}
</script>

<template>
  <v-container fluid>
    <template v-if="player">
      <v-card class="mb-4">
        <v-card-title class="d-flex align-center" style="gap: 8px">
          <span
            v-if="countryFlag(player.country)"
            :class="countryFlag(player.country)"
            :title="countryName(player.country)"
            style="font-size: 1.4em"
          />
          <span>{{ player.title ? `${player.title} ` : "" }}{{ player.name }}</span>
          <a :href="fideProfileUrl(player.fideid)" target="_blank" rel="noopener" :title="t('links.fideProfile')">
            <img src="/icons/fide.png" width="16" height="16" alt="FIDE" />
          </a>
          <a :href="lichessUrl(player.fideid, player.name)" target="_blank" rel="noopener" :title="t('links.lichess')">
            <img src="/icons/lichess.png" width="16" height="16" alt="Lichess" />
          </a>
        </v-card-title>
        <v-card-text>
          <p v-if="player.age != null">{{ t("table.age") }}: {{ player.age }}</p>
          <p v-if="player.rank_world_standard != null">
            {{ t("pages.rankWorld") }}: #{{ player.rank_world_standard }} &middot;
            {{ t("pages.rankCountry") }}: #{{ player.rank_country_standard }}
          </p>
          <v-table density="compact">
            <thead>
              <tr>
                <th>{{ t("filters.timeControl") }}</th>
                <th>{{ t("table.rating") }}</th>
                <th>{{ t("pages.maxRating") }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="c in cadenceRows" :key="c.key">
                <td>{{ c.label }}</td>
                <td>{{ c.rating ?? "-" }}</td>
                <td>{{ c.max ?? "-" }}</td>
              </tr>
            </tbody>
          </v-table>
        </v-card-text>
      </v-card>
      <v-card class="mb-4" v-if="yearlyStats?.length">
        <v-card-title>{{ t("pages.yearlyActivity") }}</v-card-title>
        <v-table density="compact">
          <thead>
            <tr>
              <th>{{ t("filters.year") }}</th>
              <th>{{ t("filters.standard") }}</th>
              <th>{{ t("filters.rapid") }}</th>
              <th>{{ t("filters.blitz") }}</th>
              <th>{{ t("table.gamesTotal") }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="y in yearlyStats" :key="y.year">
              <td>{{ y.year }}</td>
              <td>
                <span class="d-inline-block text-right" style="width: 2em">{{ y.games_standard }}</span>
                <span :class="{ 'text-red': (y.delta_standard ?? 0) < 0, 'text-green': (y.delta_standard ?? 0) > 0 }">{{ fmtDelta(y.delta_standard) }}</span>
              </td>
              <td>
                <span class="d-inline-block text-right" style="width: 2em">{{ y.games_rapid }}</span>
                <span :class="{ 'text-red': (y.delta_rapid ?? 0) < 0, 'text-green': (y.delta_rapid ?? 0) > 0 }">{{ fmtDelta(y.delta_rapid) }}</span>
              </td>
              <td>
                <span class="d-inline-block text-right" style="width: 2em">{{ y.games_blitz }}</span>
                <span :class="{ 'text-red': (y.delta_blitz ?? 0) < 0, 'text-green': (y.delta_blitz ?? 0) > 0 }">{{ fmtDelta(y.delta_blitz) }}</span>
              </td>
              <td>{{ y.games_total }}</td>
            </tr>
          </tbody>
        </v-table>
      </v-card>
      <v-card>
        <v-card-title>{{ t("pages.ratingHistory") }}</v-card-title>
        <div class="pa-4">
          <Line v-if="!historyPending && chartData.labels.length" :data="chartData" :options="chartOptions" />
          <p v-else class="text-medium-emphasis">{{ t("pages.loadingHistory") }}</p>
        </div>
      </v-card>
    </template>
    <v-alert v-else type="warning">{{ t("pages.playerNotFound") }}</v-alert>
  </v-container>
</template>
