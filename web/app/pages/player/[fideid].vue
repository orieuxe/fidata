<script setup lang="ts">
import { computed, ref } from "vue";
import { useAsyncData, useRoute } from "#app";
import { useI18n } from "#i18n";
import { Line } from "vue-chartjs";
import type { PlayerProfile, PlayerYearlyStat, Rating } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions } from "~/composables/useFilterOptions";
import PlayerLinks from "~/components/PlayerLinks.vue";
import PlayerCadenceCard from "~/components/PlayerCadenceCard.vue";

const route = useRoute();
const { get } = useApi();
const { t } = useI18n();
const { countryName, countryFlag } = await useCountryOptions();

const fideid = computed(() => Number(route.params.fideid));

const { data: profileRows } = await useAsyncData<PlayerProfile[]>(
  () => `player-profile-${fideid.value}`,
  (_nuxtApp, { signal }) =>
    get<PlayerProfile[]>("/rpc/player_profile", { p_fideid: String(fideid.value) }, { signal }),
  { watch: [fideid] },
);
const player = computed(() => profileRows.value?.[0] ?? null);

const { data: history, pending: historyPending } = await useAsyncData<Rating[]>(
  () => `player-history-${fideid.value}`,
  (_nuxtApp, { signal }) =>
    get<Rating[]>("/ratings", {
      fideid: `eq.${fideid.value}`,
      order: "period.asc",
      select: "period,rating,rating_type",
    }, { signal }),
  { watch: [fideid] },
);

const { data: yearlyStats } = await useAsyncData<PlayerYearlyStat[]>(
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
    {
      key: "standard",
      label: t("filters.standard"),
      color: CADENCE_COLORS.standard,
      rating: p.rating_standard,
      max: p.max_standard,
      games12m: p.games_12m_standard,
      eloRankWorld: p.rank_world_standard,
      eloRankCountry: p.rank_country_standard,
      activityRankWorld: p.rank_activity_world_standard,
      activityRankCountry: p.rank_activity_country_standard,
      totalWorld: p.total_activity_world_standard,
      totalCountry: p.total_activity_country_standard,
    },
    {
      key: "rapid",
      label: t("filters.rapid"),
      color: CADENCE_COLORS.rapid,
      rating: p.rating_rapid,
      max: p.max_rapid,
      games12m: p.games_12m_rapid,
      eloRankWorld: p.rank_world_rapid,
      eloRankCountry: p.rank_country_rapid,
      activityRankWorld: p.rank_activity_world_rapid,
      activityRankCountry: p.rank_activity_country_rapid,
      totalWorld: p.total_activity_world_rapid,
      totalCountry: p.total_activity_country_rapid,
    },
    {
      key: "blitz",
      label: t("filters.blitz"),
      color: CADENCE_COLORS.blitz,
      rating: p.rating_blitz,
      max: p.max_blitz,
      games12m: p.games_12m_blitz,
      eloRankWorld: p.rank_world_blitz,
      eloRankCountry: p.rank_country_blitz,
      activityRankWorld: p.rank_activity_world_blitz,
      activityRankCountry: p.rank_activity_country_blitz,
      totalWorld: p.total_activity_world_blitz,
      totalCountry: p.total_activity_country_blitz,
    },
  ] as const;
});

const RANGE_YEARS = { "1y": 1, "5y": 5, "10y": 10 } as const;
const range = ref<"1y" | "5y" | "10y" | "all">("all");

const filteredHistory = computed(() => {
  const rows = history.value ?? [];
  if (range.value === "all" || !rows.length) return rows;
  const cutoff = new Date(rows[rows.length - 1]!.period);
  cutoff.setFullYear(cutoff.getFullYear() - RANGE_YEARS[range.value]);
  const cutoffStr = cutoff.toISOString().slice(0, 10);
  return rows.filter((r) => r.period >= cutoffStr);
});

const chartData = computed(() => {
  const rows = filteredHistory.value;
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

const chartOptions = { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: "bottom" as const } } };

const tab = ref<"history" | "activity">("history");

function fmtDelta(delta: number | null) {
  if (delta == null) return "";
  return delta > 0 ? `+${delta}` : `${delta}`;
}

</script>

<template>
  <v-container fluid>
    <template v-if="player">
      <v-card class="mb-4">
        <v-card-text>
          <div class="d-flex flex-wrap align-center justify-space-between w-100">
            <div class="d-flex align-center" style="gap: 12px">
              <span
                v-if="countryFlag(player.country)"
                :class="countryFlag(player.country)"
                :title="countryName(player.country)"
                style="font-size: 2.2em; line-height: 1"
              />
              <div>
                <div class="d-flex align-center flex-wrap" style="gap: 8px">
                  <v-chip v-if="player.title" color="amber-darken-2" variant="flat" class="font-weight-bold" density="compact" style="padding-inline: 8px">
                    {{ player.title }}
                  </v-chip>
                  <span class="text-h5 font-weight-medium">{{ player.name }}</span>
                </div>
                <div class="text-body-2 text-medium-emphasis">
                  {{ countryName(player.country) }}
                  <template v-if="player.age != null"> &middot; {{ t("pages.ageYears", { n: player.age }) }} </template>
                </div>
              </div>
            </div>
            <div>
              <PlayerLinks :fideid="player.fideid" :name="player.name" :size="16" />
            </div>
          </div>
        </v-card-text>
      </v-card>

      <v-row class="mb-4" dense>
        <v-col v-for="c in cadenceRows" :key="c.key" cols="4">
          <PlayerCadenceCard
            :label="c.label"
            :color="c.color"
            :rating="c.rating"
            :max="c.max"
            :elo-rank-world="c.eloRankWorld"
            :elo-rank-country="c.eloRankCountry"
            :elo-total-world="c.totalWorld"
            :elo-total-country="c.totalCountry"
            :games12m="c.games12m"
            :activity-rank-world="c.activityRankWorld"
            :activity-rank-country="c.activityRankCountry"
            :activity-total-world="c.totalWorld"
            :activity-total-country="c.totalCountry"
            :country-name="countryName(player.country)"
            :country-flag-class="countryFlag(player.country)"
          />
        </v-col>
      </v-row>

      <v-card>
        <v-tabs v-model="tab">
          <v-tab value="history">{{ t("pages.ratingHistory") }}</v-tab>
          <v-tab value="activity">{{ t("pages.yearlyActivity") }}</v-tab>
        </v-tabs>
        <v-divider />
        <v-window v-model="tab">
          <v-window-item value="history">
            <div class="d-flex justify-end pa-4 pb-0">
              <v-btn-toggle v-model="range" mandatory density="compact" variant="outlined" divided color="primary">
                <v-btn value="1y" size="small">{{ t("pages.range1y") }}</v-btn>
                <v-btn value="5y" size="small">{{ t("pages.range5y") }}</v-btn>
                <v-btn value="10y" size="small">{{ t("pages.range10y") }}</v-btn>
                <v-btn value="all" size="small">{{ t("pages.rangeAll") }}</v-btn>
              </v-btn-toggle>
            </div>
            <div class="pa-4" style="height: 320px">
              <Line v-if="!historyPending && chartData.labels.length" :data="chartData" :options="chartOptions" />
              <p v-else class="text-medium-emphasis">{{ t("pages.loadingHistory") }}</p>
            </div>
          </v-window-item>
          <v-window-item value="activity">
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
                  <span class="ml-1" :class="{ 'text-red': (y.delta_standard ?? 0) < 0, 'text-green': (y.delta_standard ?? 0) > 0 }">{{ fmtDelta(y.delta_standard) }}</span>
                </td>
                <td>
                  <span class="d-inline-block text-right" style="width: 2em">{{ y.games_rapid }}</span>
                  <span class="ml-1" :class="{ 'text-red': (y.delta_rapid ?? 0) < 0, 'text-green': (y.delta_rapid ?? 0) > 0 }">{{ fmtDelta(y.delta_rapid) }}</span>
                </td>
                <td>
                  <span class="d-inline-block text-right" style="width: 2em">{{ y.games_blitz }}</span>
                  <span class="ml-1" :class="{ 'text-red': (y.delta_blitz ?? 0) < 0, 'text-green': (y.delta_blitz ?? 0) > 0 }">{{ fmtDelta(y.delta_blitz) }}</span>
                </td>
                <td>{{ y.games_total }}</td>
              </tr>
              </tbody>
            </v-table>
          </v-window-item>
        </v-window>
      </v-card>
    </template>
    <v-alert v-else type="warning">{{ t("pages.playerNotFound") }}</v-alert>
  </v-container>
</template>