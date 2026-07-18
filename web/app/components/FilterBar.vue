<script setup lang="ts">
import { useI18n } from "#i18n";

// Shared year/country/time-control/title/sex/age filter row -- identical
// markup used to be duplicated across index.vue, movers.vue and active.vue.
// Options are still built per-page (useFilterOptions.ts), since which
// options are offered (all-time year, all time-controls...) differs per
// page; this component only owns the layout + v-model wiring.
defineProps<{
  yearOptions: { title: string; value: unknown }[];
  countryOptions: { title: string; value: string | null }[];
  countryFlag: (code: string | null) => string | null;
  ratingTypeOptions: { title: string; value: string | null }[];
  titleOptions: { title: string; value: string }[];
  sexOptions: { title: string; value: string | null }[];
}>();

const { t } = useI18n();

const year = defineModel<unknown>("year", { required: true });
const country = defineModel<string | null>("country", { required: true });
const ratingType = defineModel<string | null>("ratingType", { required: true });
const titles = defineModel<string[]>("titles", { required: true });
const sex = defineModel<string | null>("sex", { required: true });
const minAge = defineModel<number | null>("minAge", { required: true });
const maxAge = defineModel<number | null>("maxAge", { required: true });
</script>

<template>
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
    <v-col cols="12" sm="6" md="2">
      <v-select v-model="sex" :items="sexOptions" :label="t('filters.sex')" density="compact" clearable />
    </v-col>
    <v-col cols="6" md="1">
      <v-text-field v-model.number="minAge" type="number" :label="t('filters.minAge')" density="compact" />
    </v-col>
    <v-col cols="6" md="1">
      <v-text-field v-model.number="maxAge" type="number" :label="t('filters.maxAge')" density="compact" />
    </v-col>
  </v-row>
</template>
