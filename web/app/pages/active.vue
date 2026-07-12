<script setup lang="ts">
import { ref, computed } from "vue";
import { useAsyncData } from "#app";
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

const { data: players, pending, refresh } = await useAsyncData<ActivePlayer[]>(
  "most-active",
  (_nuxtApp, { signal }) =>
    get<ActivePlayer[]>("/rpc/most_active_players", {
      ...(year.value != null && { p_year: String(year.value) }),
      ...(country.value && { p_country: country.value }),
      ...(ratingType.value && { p_rating_type: ratingType.value }),
      ...(titles.value.length && { p_titles: `{${titles.value.join(",")}}` }),
      ...(minAge.value != null && { p_min_age: String(minAge.value) }),
      ...(maxAge.value != null && { p_max_age: String(maxAge.value) }),
      p_limit: String(limit.value),
    }, { signal }),
  { watch: [year, country, ratingType, titles, minAge, maxAge, limit] },
);

const rows = computed(() => (players.value ?? []).map((p, i) => ({ ...p, rank: i + 1 })));

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
          <v-col cols="6" md="1">
            <v-select v-model="limit" :items="limitOptions" :label="t('filters.limit')" density="compact" />
          </v-col>
        </v-row>
        <p v-if="year == null" class="text-caption text-medium-emphasis">
          {{ t("pages.allTimeWarning") }}
        </p>
      </v-card-text>
      <v-data-table :headers="headers" :items="rows" :loading="pending" :items-per-page="25" density="compact">
        <template #item.name="{ item }">
          <div class="d-flex align-center" style="gap: 6px">
            <a :href="fideProfileUrl(item.fideid)" target="_blank" rel="noopener" :title="t('links.fideProfile')">
              <img src="/icons/fide.png" width="14" height="14" alt="FIDE" />
            </a>
            <a :href="lichessUrl(item.fideid, item.name)" target="_blank" rel="noopener" :title="t('links.lichess')">
              <img src="/icons/lichess.png" width="14" height="14" alt="Lichess" />
            </a>
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
    </v-card>
  </v-container>
</template>
