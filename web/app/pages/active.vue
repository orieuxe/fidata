<script setup lang="ts">
import { ref, computed, watch } from "vue";
import { useI18n } from "#i18n";
import type { ActivePlayer } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions, useYearOptions, useRatingTypeOptions, useBaseHeaders } from "~/composables/useFilterOptions";
import { fideProfileUrl, lichessUrl } from "~/utils/links";
import { TITLE_OPTIONS, LIMIT_OPTIONS } from "~/utils/filterOptions";

const { get } = useApi();
const { t } = useI18n();

const { currentYear, yearOptions } = useYearOptions(true);
const { countryOptions, countryName, countryFlag } = await useCountryOptions();
const ratingTypeOptions = useRatingTypeOptions(true);

const titleOptions = TITLE_OPTIONS;
const limitOptions = LIMIT_OPTIONS;

const year = ref<number | null>(currentYear);
const country = ref<string | null>(null);
const ratingType = ref<string | null>("standard");
const titles = ref<string[]>([]);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);
const limit = ref<number>(25);

const allRows = ref<ActivePlayer[]>([]);
const offset = ref(0);
const finished = ref(false);
const pending = ref(false);

function buildParams(off: number) {
  return {
    ...(year.value != null && { p_year: String(year.value) }),
    ...(country.value && { p_country: country.value }),
    ...(ratingType.value && { p_rating_type: ratingType.value }),
    ...(titles.value.length && { p_titles: `{${titles.value.join(",")}}` }),
    ...(minAge.value != null && { p_min_age: String(minAge.value) }),
    ...(maxAge.value != null && { p_max_age: String(maxAge.value) }),
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
  const data = await get<ActivePlayer[]>("/rpc/most_active_players", buildParams(0));
  if (token !== requestToken) return;
  allRows.value = data;
  offset.value = data.length;
  finished.value = data.length < limit.value;
  pending.value = false;
}

watch([year, country, ratingType, titles, minAge, maxAge, limit], loadInitial);
await loadInitial();

async function onLoad({ done }: { done: (status: "ok" | "error" | "empty") => void }) {
  if (finished.value) {
    done("empty");
    return;
  }
  const token = requestToken;
  try {
    const data = await get<ActivePlayer[]>("/rpc/most_active_players", buildParams(offset.value));
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
  { title: t("table.rating"), key: "rating" },
  { title: t("table.age"), key: "age" },
  { title: t("table.games"), key: "total_games" },
]);
</script>

<template>
  <v-container fluid>
    <v-card :title="t('pages.mostActivePlayers')">
      <v-card-text>
        <v-row dense>
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
          <v-col cols="6" md="2">
            <v-text-field v-model.number="minAge" type="number" :label="t('filters.minAge')" density="compact" />
          </v-col>
          <v-col cols="6" md="2">
            <v-text-field v-model.number="maxAge" type="number" :label="t('filters.maxAge')" density="compact" />
          </v-col>
        </v-row>
        <p v-if="year == null" class="text-caption text-medium-emphasis">
          {{ t("pages.allTimeWarning") }}
        </p>
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
          </v-data-table>
        </template>
      </v-infinite-scroll>
    </v-card>
  </v-container>
</template>
