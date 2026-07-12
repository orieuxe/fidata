<script setup lang="ts">
import type { RatingChange, Country } from "~/types/api";

const { get } = useApi();
const { t } = useI18n();

const currentYear = new Date().getFullYear();
const years = Array.from({ length: currentYear - 2015 + 1 }, (_, i) => currentYear - i);
const yearOptions = years.map((y) => ({ title: String(y), value: y }));

const { data: countries } = await useAsyncData("countries", () =>
  get<Country[]>("/countries"),
);
const countryOptions = computed(() => [
  { title: t("filters.allCountries"), value: null },
  ...(countries.value ?? []).map((c) => ({ title: c.code, value: c.code })),
]);

const ratingTypeOptions = computed(() => [
  { title: t("filters.standard"), value: "standard" },
  { title: t("filters.rapid"), value: "rapid" },
  { title: t("filters.blitz"), value: "blitz" },
]);

const titleOptions = ["GM", "IM", "FM", "CM", "WGM", "WIM", "WFM", "WCM", "UNTITLED"];

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

const { data: players, pending } = await useAsyncData<RatingChange[]>(
  "rating-change",
  () =>
    get<RatingChange[]>("/rpc/rating_change", {
      p_year: String(year.value),
      ...(country.value && { p_country: country.value }),
      ...(ratingType.value && { p_rating_type: ratingType.value }),
      ...(titles.value.length && { p_titles: `{${titles.value.join(",")}}` }),
      ...(minAge.value != null && { p_min_age: String(minAge.value) }),
      ...(maxAge.value != null && { p_max_age: String(maxAge.value) }),
      p_direction: direction.value,
      p_limit: "50",
    }),
  { watch: [year, country, ratingType, titles, minAge, maxAge, direction] },
);

const rows = computed(() => (players.value ?? []).map((p, i) => ({ ...p, rank: i + 1 })));

const headers = computed(() => [
  { title: t("table.rank"), key: "rank", width: 60 },
  { title: t("table.name"), key: "name" },
  { title: t("table.country"), key: "country" },
  { title: t("table.title"), key: "title" },
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
            <v-autocomplete v-model="country" :items="countryOptions" :label="t('filters.country')" density="compact" />
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
        <template #item.delta="{ item }">
          <span :class="{ 'text-red': item.delta < 0, 'text-green': item.delta > 0 }">{{ item.delta > 0 ? `+${item.delta}` : item.delta }}</span>
        </template>
      </v-data-table>
    </v-card>
  </v-container>
</template>
