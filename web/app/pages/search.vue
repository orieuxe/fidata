<script setup lang="ts">
import { ref, watch, computed } from "vue";
import { useI18n } from "#i18n";
import { useDisplay } from "vuetify";
import type { SearchPlayer } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions } from "~/composables/useFilterOptions";
import { useUrlFilters } from "~/composables/useUrlFilters";
import { useInfiniteRows } from "~/composables/useInfiniteRows";
import PlayerTable from "~/components/PlayerTable.vue";

const { get } = useApi();
const { t } = useI18n();
const { xs } = useDisplay();

const { countryName, countryFlag } = await useCountryOptions();

const PAGE_SIZE = 25;

const name = ref("");
useUrlFilters({ name });
const debouncedName = ref("");
let debounceTimer: ReturnType<typeof setTimeout>;
watch(name, (value) => {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => { debouncedName.value = value.trim(); }, 300);
});

function fetchPage(off: number, limit: number) {
  if (debouncedName.value.length < 2) return Promise.resolve([]);
  return get<SearchPlayer[]>("/rpc/search_players", {
    p_name: debouncedName.value,
    p_limit: String(limit),
    p_offset: String(off),
  });
}

const { rows, pending, loadInitial, onLoad } = useInfiniteRows(fetchPage, () => PAGE_SIZE);
watch(debouncedName, loadInitial, { immediate: true });

// No title column -- it renders inline before the name (see PlayerTable's
// #item.name). Country comes before name, same position as every other
// table.
const headers = computed(() => [
  { title: t("table.country"), key: "country", width: xs.value ? 36 : 50 },
  { title: t("table.name"), key: "name" },
  // Full "Standard"/"Rapide"/"Blitz" header text forces these columns
  // wider than their 4-digit content needs -- on mobile there's no room
  // for that, so abbreviate to 3 letters instead of losing a column. On
  // desktop, table-layout:fixed means this width has to fit that full text
  // too, not just the 4-digit rating.
  { title: xs.value ? t("filters.standard").slice(0, 3) : t("filters.standard"), key: "rating_standard", width: xs.value ? 56 : 90 },
  { title: xs.value ? t("filters.rapid").slice(0, 3) : t("filters.rapid"), key: "rating_rapid", width: xs.value ? 56 : 90 },
  { title: xs.value ? t("filters.blitz").slice(0, 3) : t("filters.blitz"), key: "rating_blitz", width: xs.value ? 56 : 90 },
  { title: t("table.age"), key: "age", width: xs.value ? 48 : 80 },
]);
</script>

<template>
  <v-container fluid>
    <v-card :title="t('pages.searchPlayers')">
      <v-card-text class="d-flex flex-column align-center">
        <v-text-field
          v-model="name"
          :label="t('filters.playerName')"
          prepend-inner-icon="mdi-magnify"
          density="compact"
          clearable
          autofocus
          style="max-width: 400px; width: 100%"
        />
        <p v-if="name.trim().length > 0 && name.trim().length < 2" class="text-caption text-medium-emphasis">
          {{ t("pages.searchHint") }}
        </p>
      </v-card-text>
      <v-infinite-scroll v-if="debouncedName.length >= 2" @load="onLoad" style="max-width: 800px; margin: 0 auto">
        <template #default>
          <PlayerTable
            :headers="headers"
            :items="rows"
            :loading="pending"
            :no-data-text="t('pages.searchNoResults')"
            :country-flag="countryFlag"
            :country-name="countryName"
          />
        </template>
      </v-infinite-scroll>
    </v-card>
  </v-container>
</template>
