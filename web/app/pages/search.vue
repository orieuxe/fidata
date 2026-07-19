<script setup lang="ts">
import { ref, watch, computed } from "vue";
import { useI18n, useLocalePath } from "#i18n";
import { useDisplay } from "vuetify";
import type { SearchPlayer } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions } from "~/composables/useFilterOptions";
import { useUrlFilters } from "~/composables/useUrlFilters";

const { get } = useApi();
const { t } = useI18n();
const localePath = useLocalePath();
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

const rows = ref<SearchPlayer[]>([]);
const offset = ref(0);
const finished = ref(false);
const pending = ref(false);

// ponytail: plain sequence token instead of AbortController -- infinite
// scroll's own onLoad already serializes chunk fetches, this only guards
// against a name change racing an in-flight one.
let requestToken = 0;
async function loadInitial() {
  const token = ++requestToken;
  if (debouncedName.value.length < 2) {
    rows.value = [];
    offset.value = 0;
    finished.value = true;
    return;
  }
  pending.value = true;
  const data = await get<SearchPlayer[]>("/rpc/search_players", {
    p_name: debouncedName.value,
    p_limit: String(PAGE_SIZE),
    p_offset: "0",
  });
  if (token !== requestToken) return;
  rows.value = data;
  offset.value = data.length;
  finished.value = data.length < PAGE_SIZE;
  pending.value = false;
}

watch(debouncedName, loadInitial, { immediate: true });

async function onLoad({ done }: { done: (status: "ok" | "error" | "empty") => void }) {
  if (finished.value) {
    done("empty");
    return;
  }
  const token = requestToken;
  try {
    const data = await get<SearchPlayer[]>("/rpc/search_players", {
      p_name: debouncedName.value,
      p_limit: String(PAGE_SIZE),
      p_offset: String(offset.value),
    });
    if (token !== requestToken) {
      done("ok");
      return;
    }
    rows.value = [...rows.value, ...data];
    offset.value += data.length;
    if (data.length < PAGE_SIZE) finished.value = true;
    done(data.length ? "ok" : "empty");
  } catch {
    done("error");
  }
}

const headers = computed(() =>
  [
    { title: t("table.name"), key: "name" },
    { title: t("table.country"), key: "country", width: xs.value ? 36 : 50 },
    { title: t("table.title"), key: "title", width: 70 },
    // Full "Standard"/"Rapide"/"Blitz" header text forces these columns
    // wider than their 4-digit content needs -- on mobile there's no room
    // for that, so abbreviate to 3 letters instead of losing a column.
    { title: xs.value ? t("filters.standard").slice(0, 3) : t("filters.standard"), key: "rating_standard", width: 56 },
    { title: xs.value ? t("filters.rapid").slice(0, 3) : t("filters.rapid"), key: "rating_rapid", width: 56 },
    { title: xs.value ? t("filters.blitz").slice(0, 3) : t("filters.blitz"), key: "rating_blitz", width: 56 },
    { title: t("table.age"), key: "age", width: xs.value ? 48 : 80 },
  ].filter((h) => !xs.value || h.key !== "title"),
);
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
          <v-data-table
            :headers="headers"
            :items="rows"
            :loading="pending"
            items-per-page="-1"
            hide-default-footer
            density="compact"
            :no-data-text="t('pages.searchNoResults')"
          >
            <template #header.country="{ column }">
              <v-icon icon="mdi-flag-outline" size="16" :title="column.title" />
            </template>
            <template #item.name="{ item }">
              <NuxtLink :to="localePath(`/player/${item.fideid}`)" :title="item.name" class="player-name-link text-high-emphasis">{{ item.name }}</NuxtLink>
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

<style scoped>
:deep(table) {
  table-layout: fixed;
}
:deep(.v-data-table__td),
:deep(.v-data-table__th) {
  padding-inline: 6px !important;
}
.player-name-link {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: rgb(var(--v-theme-primary));
  text-decoration: underline;
  text-decoration-color: transparent;
  transition: text-decoration-color 0.15s;
}
.player-name-link:hover {
  text-decoration-color: currentColor;
}
</style>
