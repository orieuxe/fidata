<script setup lang="ts">
import { ref, computed, watch, onMounted } from "vue";
import { useI18n, useLocalePath } from "#i18n";
import { useDisplay } from "vuetify";
import type { RatingChange } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useYearOptions, useRatingTypeOptions, useBaseHeaders, useTitleOptions, useSexOptions } from "~/composables/useFilterOptions";
import { useUrlFilters } from "~/composables/useUrlFilters";
import { LIMIT_OPTIONS, yearFilterRange, type YearFilterValue } from "~/utils/filterOptions";
import FilterBar from "~/components/FilterBar.vue";

const { get } = useApi();
const { t } = useI18n();
const localePath = useLocalePath();
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

const allRows = ref<RatingChange[]>([]);
const offset = ref(0);
const finished = ref(false);
const pending = ref(false);

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
    p_direction: direction.value,
    p_limit: String(limit.value),
    p_offset: String(off),
  };
}

// ponytail: plain sequence token instead of AbortController -- infinite
// scroll's own onLoad already serializes chunk fetches, this only guards
// against a filter change racing an in-flight one.
let requestToken = 0;
async function loadInitial() {
  const token = ++requestToken;
  pending.value = true;
  const data = await get<RatingChange[]>("/rpc/rating_change", buildParams(0));
  if (token !== requestToken) return;
  allRows.value = data;
  offset.value = data.length;
  finished.value = data.length < limit.value;
  pending.value = false;
}

watch([year, country, ratingType, titles, sex, minAge, maxAge, direction, limit], loadInitial);
await loadInitial();

async function onLoad({ done }: { done: (status: "ok" | "error" | "empty") => void }) {
  if (finished.value) {
    done("empty");
    return;
  }
  const token = requestToken;
  try {
    const data = await get<RatingChange[]>("/rpc/rating_change", buildParams(offset.value));
    if (token !== requestToken) {
      done("ok");
      return;
    }
    allRows.value = [...allRows.value, ...data];
    offset.value += data.length;
    if (data.length < limit.value) finished.value = true;
    done(data.length ? "ok" : "empty");
  } catch {
    done("error");
  }
}

const rows = computed(() => allRows.value.map((p, i) => ({ ...p, rank: i + 1 })));

// v-data-table caches column widths per key on first render and doesn't
// react to width/column-count changes after that -- SSR always guesses xs
// (no real viewport to measure), so once the client corrects `xs` post-
// mount, the table would otherwise keep rendering the wrong (SSR-guessed)
// column layout forever. Force one clean remount right after mount, keyed
// on the now-correct value, to pick up the real widths.
const mounted = ref(false);
onMounted(() => { mounted.value = true; });
const tableKey = computed(() => (mounted.value ? `full-${xs.value}` : "ssr"));

// Reorders useBaseHeaders' [name, country, title] so flag sits right
// before the name -- same compact layout as index.vue, local to this page
// so it doesn't touch the shared composable. Rank has no column on mobile
// (row order already conveys it, and there's no width to spare); title has
// no column either -- it renders inline before the name (see #item.name)
// instead of taking a column of its own.
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
          <v-data-table
            :key="tableKey"
            :headers="headers"
            :items="rows"
            :loading="pending"
            items-per-page="-1"
            hide-default-footer
            density="compact"
          >
            <template #header.country="{ column }">
              <v-icon icon="mdi-flag-outline" size="16" :title="column.title" />
            </template>
            <template #item.name="{ item }">
              <span class="player-cell" :title="item.name">
                <span v-if="item.title" class="player-title-prefix">{{ item.title }}</span>
                <NuxtLink :to="localePath(`/player/${item.fideid}`)" class="player-name-link text-high-emphasis">{{ item.name }}</NuxtLink>
              </span>
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
            <template #item.delta="{ item }">
              <span :class="{ 'text-red': item.delta < 0, 'text-green': item.delta > 0 }">{{ item.delta > 0 ? `+${item.delta}` : item.delta }}</span>
            </template>
          </v-data-table>
        </template>
      </v-infinite-scroll>
    </v-card>
  </v-container>
</template>

<style scoped>
:deep(table) {
  table-layout: fixed;
}
:deep(.v-data-table__td),
:deep(.v-data-table__th) {
  padding-inline: 6px !important;
}
.player-cell {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.player-title-prefix {
  color: #ff8f00; /* amber-darken-2, same as the title chip on the player page */
  font-weight: 700;
  font-size: 0.85em;
  margin-right: 4px;
}
.player-name-link {
  color: rgb(var(--v-theme-primary));
  text-decoration: underline;
  text-decoration-color: transparent;
  transition: text-decoration-color 0.15s;
}
.player-name-link:hover {
  text-decoration-color: currentColor;
}
</style>
