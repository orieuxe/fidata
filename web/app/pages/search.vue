<script setup lang="ts">
import { ref, watch } from "vue";
import { useI18n } from "#i18n";
import type { SearchPlayer } from "~/types/api";
import { useApi } from "~/composables/useApi";
import { useCountryOptions } from "~/composables/useFilterOptions";
import { fideProfileUrl, lichessUrl } from "~/utils/links";

const { get } = useApi();
const { t } = useI18n();

const { countryName, countryFlag } = await useCountryOptions();

const PAGE_SIZE = 25;

const name = ref("");
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

const headers = [
  { title: t("table.name"), key: "name" },
  { title: t("table.country"), key: "country" },
  { title: t("table.title"), key: "title" },
  { title: t("filters.standard"), key: "rating_standard" },
  { title: t("filters.rapid"), key: "rating_rapid" },
  { title: t("filters.blitz"), key: "rating_blitz" },
  { title: t("table.age"), key: "age" },
];
</script>

<template>
  <v-container fluid>
    <v-card :title="t('pages.searchPlayers')">
      <v-card-text>
        <v-text-field
          v-model="name"
          :label="t('filters.playerName')"
          prepend-inner-icon="mdi-magnify"
          density="compact"
          clearable
          autofocus
        />
        <p v-if="name.trim().length > 0 && name.trim().length < 2" class="text-caption text-medium-emphasis">
          {{ t("pages.searchHint") }}
        </p>
      </v-card-text>
      <v-infinite-scroll v-if="debouncedName.length >= 2" @load="onLoad">
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
        </template>
      </v-infinite-scroll>
    </v-card>
  </v-container>
</template>
