<script setup lang="ts">
import { useI18n } from "#i18n";
import { formatNumber } from "~/utils/format";
import RankChipPair from "./RankChipPair.vue";

defineProps<{
  label: string;
  color: string;
  rating: number | null;
  max: number | null;
  eloRankWorld: number | null;
  eloRankCountry: number | null;
  eloTotalWorld: number | null;
  eloTotalCountry: number | null;
  games12m: number | null;
  activityRankWorld: number | null;
  activityRankCountry: number | null;
  activityTotalWorld: number | null;
  activityTotalCountry: number | null;
  countryName?: string | null;
  countryFlagClass?: string | null;
}>();

const { t, locale } = useI18n();
</script>

<template>
  <v-card class="text-center pa-2 pa-sm-4" :style="{ borderTop: `3px solid ${color}` }">
    <div class="text-caption text-uppercase text-medium-emphasis">{{ label }}</div>
    <div class="text-h5 text-sm-h4 font-weight-bold my-1">
      {{ rating ?? "—" }}
      <span v-if="max != null" class="text-caption text-medium-emphasis font-weight-regular">({{ t("pages.maxShort") }} {{ max }})</span>
    </div>
    <RankChipPair
      v-if="eloRankWorld != null"
      class="mt-1"
      :rank-world="eloRankWorld"
      :total-world="eloTotalWorld"
      :rank-country="eloRankCountry"
      :total-country="eloTotalCountry"
      :country-name="countryName"
      :country-flag-class="countryFlagClass"
    />
    <template v-if="games12m != null">
      <v-divider class="my-2" />
      <div class="text-caption text-medium-emphasis">{{ t("pages.gamesLast12m", { n: formatNumber(games12m, locale) }) }}</div>
      <RankChipPair
        class="mt-1"
        :rank-world="activityRankWorld"
        :total-world="activityTotalWorld"
        :rank-country="activityRankCountry"
        :total-country="activityTotalCountry"
        :country-name="countryName"
        :country-flag-class="countryFlagClass"
      />
    </template>
  </v-card>
</template>
