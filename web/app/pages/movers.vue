<script setup lang="ts">
import { ref, computed, watch } from "vue";
import { useI18n } from "#i18n";
import type { RatingChange } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useYearOptions, useRatingTypeOptions, useBaseHeaders } from "~/composables/useFilterOptions";
import { fideProfileUrl, lichessUrl } from "~/utils/links";
import { TITLE_OPTIONS, LIMIT_OPTIONS } from "~/utils/filterOptions";

const { get } = useApi();
const { t } = useI18n();

const { currentYear, yearOptions } = useYearOptions(false);
const { countryOptions, countryName, countryFlag } = await useCountryOptions();
const ratingTypeOptions = useRatingTypeOptions(false);

const titleOptions = TITLE_OPTIONS;
const limitOptions = LIMIT_OPTIONS;

const directionOptions = computed(() => [
  { title: t("filters.mostImproved"), value: "gain" },
  { title: t("filters.biggestLoss"), value: "loss" },
]);

const year = ref<number>(currentYear);
const country = ref<string | null>(null);
const ratingType = ref<string>("standard");
const titles = ref<string[]>([]);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);
const direction = ref<"gain" | "loss">("gain");
const limit = ref<number>(25);

const allRows = ref<RatingChange[]>([]);
const offset = ref(0);
const finished = ref(false);
const pending = ref(false);

function buildParams(off: number) {
  return {
    p_year: String(year.value),
    ...(country.value && { p_country: country.value }),
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

watch([year, country, ratingType, titles, minAge, maxAge, direction, limit], loadInitial);
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

const baseHeaders = useBaseHeaders();
const headers = computed(() => [
  ...baseHeaders.value,
  { title: t("table.age"), key: "age" },
  { title: t("table.start"), key: "start_rating" },
  { title: t("table.end"), key: "end_rating" },
  { title: t("table.delta"), key: "delta" },
]);
</script>

<template>
  <v-container fluid>
    <v-card :title="t('pages.ratingMovers')">
      <v-card-text>
        <v-row dense>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="direction" :items="directionOptions" :label="t('filters.direction')" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="year" :items="yearOptions" :label="t('filters.year')" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-autocomplete v-model="country" :items="countryOptions" :label="t('filters.country')" density="compact">
              <template #item="{ props, item }">
                <v-list-item v-bind="props" title="">
                  <span v-if="countryFlag(item.raw?.value)" :class="countryFlag(item.raw?.value)" class="mr-2" />
                  {{ item.raw?.title ?? item.title }}
                </v-list-item>
              </template>
              <template #selection="{ item }">
                <span v-if="countryFlag(item.raw?.value)" :class="countryFlag(item.raw?.value)" class="mr-2" />
                {{ item.raw?.title ?? item.title }}
              </template>
            </v-autocomplete>
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
        </v-row>
      </v-card-text>
      <v-infinite-scroll @load="onLoad">
        <template #default>
          <v-data-table
            :headers="headers"
            :items="rows"
            :loading="pending"
            items-per-page="-1"
            hide-default-footer
            density="compact"
          >
            <template #item.name="{ item }">
              <div class="d-flex align-center" style="gap: 6px">
                <a :href="fideProfileUrl(item.fideid)" target="_blank" rel="noopener" :title="t('links.fideProfile')">
                  <img src="/icons/fide.png" width="14" height="14" alt="FIDE" />
                </a>
                <a :href="lichessUrl(item.fideid, item.name)" target="_blank" rel="noopener" :title="t('links.lichess')">
                  <img src="/icons/lichess.png" width="14" height="14" alt="Lichess" />
                </a>
                <NuxtLink :to="`/player/${item.fideid}`" :title="t('links.playerProfile')">
                  <v-icon size="14" icon="mdi-chart-line" />
                </NuxtLink>
                <span>{{ item.name }}</span>
              </div>
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
