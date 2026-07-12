<script setup lang="ts">
import type { ActivePlayer, Country } from "~/types/api";

const { get } = useApi();

const currentYear = new Date().getFullYear();
const years = Array.from({ length: currentYear - 2015 + 2 }, (_, i) => currentYear + 1 - i); // newest first, +1 = "All time"
const yearOptions = years.map((y) => (y > currentYear ? { title: "All time", value: null } : { title: String(y), value: y }));

const { data: countries } = await useAsyncData("countries", () =>
  get<Country[]>("/countries"),
);
const countryOptions = computed(() => [
  { title: "All countries", value: null },
  ...(countries.value ?? []).map((c) => ({ title: c.code, value: c.code })),
]);

const ratingTypeOptions = [
  { title: "All time controls", value: null },
  { title: "Standard", value: "standard" },
  { title: "Rapid", value: "rapid" },
  { title: "Blitz", value: "blitz" },
];

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

const headers = [
  { title: "#", key: "rank", width: 60 },
  { title: "Name", key: "name" },
  { title: "Country", key: "country" },
  { title: "Title", key: "title" },
  { title: "Rating", key: "rating" },
  { title: "Games", key: "total_games" },
];
</script>

<template>
  <v-container fluid>
    <v-card title="Most active players">
      <v-card-text>
        <v-row dense>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="year" :items="yearOptions" label="Year" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-autocomplete v-model="country" :items="countryOptions" label="Country" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="ratingType" :items="ratingTypeOptions" label="Time control" density="compact" />
          </v-col>
          <v-col cols="12" sm="6" md="2">
            <v-select v-model="titles" :items="titleOptions" label="Title" multiple chips density="compact" />
          </v-col>
          <v-col cols="6" md="2">
            <v-text-field v-model.number="minAge" type="number" label="Min age" density="compact" />
          </v-col>
          <v-col cols="6" md="2">
            <v-text-field v-model.number="maxAge" type="number" label="Max age" density="compact" />
          </v-col>
        </v-row>
        <p v-if="year == null" class="text-caption text-medium-emphasis">
          "All time" scans the full rating history and can take a while.
        </p>
      </v-card-text>
      <v-data-table :headers="headers" :items="rows" :loading="pending" :items-per-page="50" density="compact" />
    </v-card>
  </v-container>
</template>
