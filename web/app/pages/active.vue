<script setup lang="ts">
import { ref, computed, watch } from "vue";
import { useI18n } from "#i18n";
import { useDisplay } from "vuetify";
import type { ActivePlayer } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useYearOptions, useRatingTypeOptions, useBaseHeaders, useTitleOptions, useSexOptions } from "~/composables/useFilterOptions";
import { useUrlFilters } from "~/composables/useUrlFilters";
import { useInfiniteRows } from "~/composables/useInfiniteRows";
import { LIMIT_OPTIONS, yearFilterRange, type YearFilterValue } from "~/utils/filterOptions";
import FilterBar from "~/components/FilterBar.vue";
import PlayerTable from "~/components/PlayerTable.vue";

const { get } = useApi();
const { t } = useI18n();
const { xs } = useDisplay();

const { defaultYear, yearOptions } = useYearOptions(true, true);
const { countryOptions, countryName, countryFlag } = await useCountryOptions();
const ratingTypeOptions = useRatingTypeOptions(true);

const titleOptions = useTitleOptions();
const sexOptions = useSexOptions();
const limitOptions = LIMIT_OPTIONS;

const year = ref<YearFilterValue>(defaultYear);
const country = ref<string | null>(null);
const ratingType = ref<string | null>("standard");
const titles = ref<string[]>([]);
const sex = ref<string | null>(null);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);
const limit = ref<number>(25);

useUrlFilters({ year, country, ratingType, titles, sex, minAge, maxAge, limit });

function buildParams(off: number) {
  const { from, to } = yearFilterRange(year.value);
  return {
    ...(from && { p_from: from }),
    ...(to && { p_to: to }),
    ...(country.value && { p_country: country.value }),
    ...(sex.value && { p_sex: sex.value }),
    ...(ratingType.value && { p_rating_type: ratingType.value }),
    ...(titles.value.length && { p_titles: `{${titles.value.join(",")}}` }),
    ...(minAge.value != null && { p_min_age: String(minAge.value) }),
    ...(maxAge.value != null && { p_max_age: String(maxAge.value) }),
    p_limit: String(limit.value),
    p_offset: String(off),
  };
}

function fetchPage(off: number) {
  return get<ActivePlayer[]>("/rpc/most_active_players", buildParams(off));
}

const { rows: allRows, pending, loadInitial, onLoad } = useInfiniteRows(fetchPage, () => limit.value);

watch([year, country, ratingType, titles, sex, minAge, maxAge, limit], loadInitial);
await loadInitial();

const rows = computed(() => allRows.value);

// Reorders useBaseHeaders' [rank, name, country, title] so flag + title sit
// right before the name -- same compact layout as index.vue, local to this
// page so it doesn't touch the shared composable. Rank itself is dropped:
// row order already conveys it, and the column cost more width than it
// was worth, especially on mobile.
const baseHeaders = useBaseHeaders();
const headers = computed(() => {
  const base = baseHeaders.value;
  const byKey = (key: string) => base.find((h) => h.key === key)!;
  return [
    { ...byKey("country"), width: xs.value ? 36 : 50 },
    { ...byKey("title"), width: 70 },
    byKey("name"),
    { title: t("table.rating"), key: "rating", width: xs.value ? 56 : 100 },
    { title: t("table.age"), key: "age", width: xs.value ? 48 : 80 },
    { title: t("table.games"), key: "total_games", width: xs.value ? 48 : 100 },
  ].filter((h) => !xs.value || h.key !== "title");
});
</script>

<template>
  <v-container fluid>
    <v-card :title="t('pages.mostActivePlayers')">
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
        <p v-if="year == null" class="text-caption text-medium-emphasis">
          {{ t("pages.allTimeWarning") }}
        </p>
      </v-card-text>
      <v-infinite-scroll @load="onLoad" style="max-width: 700px; margin: 0 auto">
        <template #default>
          <PlayerTable
            :headers="headers"
            :items="rows"
            :loading="pending"
            :country-flag="countryFlag"
            :country-name="countryName"
          >
            <template #header.total_games="{ column }">
              <v-icon icon="mdi-chess-pawn" size="16" :title="column.title" />
            </template>
          </PlayerTable>
        </template>
      </v-infinite-scroll>
    </v-card>
  </v-container>
</template>
