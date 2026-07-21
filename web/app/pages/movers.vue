<script setup lang="ts">
import { ref, computed, watch } from "vue";
import { useI18n } from "#i18n";
import { useDisplay } from "vuetify";
import type { RatingChange } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useYearOptions, useRatingTypeOptions, useBaseHeaders, useTitleOptions, useSexOptions } from "~/composables/useFilterOptions";
import { useUrlFilters } from "~/composables/useUrlFilters";
import { useInfiniteRows } from "~/composables/useInfiniteRows";
import { LIMIT_OPTIONS, yearFilterRange, buildBaseFilterParams, type YearFilterValue } from "~/utils/filterOptions";
import FilterBar from "~/components/FilterBar.vue";
import PlayerTable from "~/components/PlayerTable.vue";

const { get } = useApi();
const { t } = useI18n();
const { xs } = useDisplay();

const { defaultYear, yearOptions } = useYearOptions(false, true);
const { countryOptions, countryName, countryFlag } = await useCountryOptions();
const ratingTypeOptions = useRatingTypeOptions(false);

const titleOptions = useTitleOptions();
const sexOptions = useSexOptions();
const limitOptions = LIMIT_OPTIONS;

const year = ref<YearFilterValue>(defaultYear);
const country = ref<string | null>(null);
const ratingType = ref<string>("standard");
const titles = ref<string[]>([]);
const sex = ref<string | null>(null);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);
const direction = ref<"gain" | "loss">("gain");
const limit = ref<number>(25);

useUrlFilters({ year, country, ratingType, titles, sex, minAge, maxAge, direction, limit });

function buildParams(off: number) {
  const { from, to } = yearFilterRange(year.value);
  return {
    ...(from && { p_from: from }),
    ...(to && { p_to: to }),
    ...buildBaseFilterParams({ country, sex, ratingType, titles, minAge, maxAge }),
    p_direction: direction.value,
    p_limit: String(limit.value),
    p_offset: String(off),
  };
}

function fetchPage(off: number) {
  return get<RatingChange[]>("/rpc/rating_change", buildParams(off));
}

const { rows: allRows, pending, loadInitial, onLoad } = useInfiniteRows(fetchPage, () => limit.value);

watch([year, country, ratingType, titles, sex, minAge, maxAge, direction, limit], loadInitial);
await loadInitial();

const rows = computed(() => allRows.value.map((p, i) => ({ ...p, rank: i + 1 })));

// Local header reorder: flag before name; no rank/title column on mobile (title renders inline in #item.name).
const baseHeaders = useBaseHeaders();
const headers = computed(() => {
  const base = baseHeaders.value;
  const byKey = (key: string) => base.find((h) => h.key === key)!;
  return [
    ...(xs.value ? [] : [{ title: t("table.rank"), key: "rank", width: 50 }]),
    { ...byKey("country"), width: xs.value ? 36 : 50 },
    byKey("name"),
    { title: t("table.age"), key: "age", width: xs.value ? 48 : 80 },
    { title: t("table.start"), key: "start_rating", width: 90 },
    { title: t("table.end"), key: "end_rating", width: xs.value ? 64 : 90 },
    { title: t("table.delta"), key: "delta", width: xs.value ? 56 : 90 },
    // On mobile, start rating is the one column dropped -- end rating +
    // delta already tell the story, and there's still no room for all four.
  ].filter((h) => !xs.value || h.key !== "start_rating");
});
</script>

<template>
  <v-container fluid>
    <v-card>
      <v-card-title class="d-flex flex-wrap align-center" style="gap: 12px">
        <span>{{ t('pages.ratingMovers') }}</span>
        <v-btn-toggle
          v-model="direction"
          mandatory
          density="compact"
          color="primary"
          divided
          elevation="3"
          :class="{ 'w-100': xs }"
        >
          <v-btn value="gain" :title="t('filters.mostImproved')" :class="{ 'flex-grow-1': xs }">
            <span style="margin-right: 8px"><v-icon icon="mdi-trending-up" /></span>
            <template v-if="!xs">{{ t('filters.mostImproved') }}</template>
          </v-btn>
          <v-btn value="loss" :title="t('filters.biggestLoss')" :class="{ 'flex-grow-1': xs }">
            <span style="margin-right: 8px"><v-icon icon="mdi-trending-down" /></span>
            <template v-if="!xs">{{ t('filters.biggestLoss') }}</template>
          </v-btn>
        </v-btn-toggle>
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
      <v-infinite-scroll @load="onLoad" style="max-width: 900px; margin: 0 auto">
        <template #default>
          <PlayerTable
            :headers="headers"
            :items="rows"
            :loading="pending"
            :country-flag="countryFlag"
            :country-name="countryName"
          >
            <template #item.delta="{ item }">
              <span :class="{ 'text-red': item.delta < 0, 'text-green': item.delta > 0 }">{{ item.delta > 0 ? `+${item.delta}` : item.delta }}</span>
            </template>
          </PlayerTable>
        </template>
      </v-infinite-scroll>
    </v-card>
  </v-container>
</template>
