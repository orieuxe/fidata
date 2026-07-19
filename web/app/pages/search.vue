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

// No title column -- renders inline in PlayerTable's #item.name.
const headers = computed(() => [
  { title: t("table.country"), key: "country", width: xs.value ? 36 : 50 },
  { title: t("table.name"), key: "name" },
  // Abbreviate on mobile to keep the column from stealing width; desktop keeps full text since table-layout:fixed sizes to it anyway.
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
          @click:clear="name = ''"
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
        <template #empty />
      </v-infinite-scroll>
    </v-card>
  </v-container>
</template>
