<script setup lang="ts">
import type { ActivePlayer, Country } from "~/types/api";

const { get } = useApi();
const { t } = useI18n();

const currentYear = new Date().getFullYear();
const years = Array.from({ length: currentYear - 2015 + 2 }, (_, i) => currentYear + 1 - i); // newest first, +1 = "All time"
const yearOptions = years.map((y) => (y > currentYear ? { title: t("filters.allTime"), value: null } : { title: String(y), value: y }));

const { data: countries } = await useAsyncData("countries", () =>
  get<Country[]>("/countries"),
);
const countryOptions = computed(() => [
  { title: t("filters.allCountries"), value: null },
  ...(countries.value ?? []).map((c) => ({ title: c.code, value: c.code })),
]);

const ratingTypeOptions = computed(() => [
  { title: t("filters.allTimeControls"), value: null },
  { title: t("filters.standard"), value: "standard" },
  { title: t("filters.rapid"), value: "rapid" },
  { title: t("filters.blitz"), value: "blitz" },
]);

const titleOptions = ["GM", "IM", "FM", "CM", "WGM", "WIM", "WFM", "WCM", "UNTITLED"];

const year = ref<number | null>(currentYear);
const country = ref<string | null>(null);
const ratingType = ref<string | null>(null);
const titles = ref<string[]>([]);
const minAge = ref<number | null>(null);
const maxAge = ref<number | null>(null);

const { data: players, pending, refresh } = await useAsyncData<ActivePlayer[]>(
  "most-active",
  () =>
    get<ActivePlayer[]>("/rpc/most_active_players", {
      ...(year.value != null && { p_year: String(year.value) }),
      ...(country.value && { p_country: country.value }),
      ...(ratingType.value && { p_rating_type: ratingType.value }),
      ...(titles.value.length && { p_titles: `{${titles.value.join(",")}}` }),
      ...(minAge.value != null && { p_min_age: String(minAge.value) }),
      ...(maxAge.value != null && { p_max_age: String(maxAge.value) }),
      p_limit: "50",
    }),
  { watch: [year, country, ratingType, titles, minAge, maxAge] },
);

const rows = computed(() => (players.value ?? []).map((p, i) => ({ ...p, rank: i + 1 })));

const headers = computed(() => [
  { title: t("table.rank"), key: "rank", width: 60 },
  { title: t("table.name"), key: "name" },
  { title: t("table.country"), key: "country" },
  { title: t("table.title"), key: "title" },
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
            <v-autocomplete v-model="country" :items="countryOptions" :label="t('filters.country')" density="compact" />
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
      </v-data-table>
    </v-card>
  </v-container>
</template>
