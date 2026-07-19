<script setup lang="ts" generic="T extends { fideid: number; name: string; country: string | null; title?: string | null }">
import { ref, computed, onMounted } from "vue";
import { useLocalePath } from "#i18n";
import { useDisplay } from "vuetify";

defineProps<{
  headers: { title: string; key: string; width?: number }[];
  items: T[];
  loading?: boolean;
  noDataText?: string;
  countryFlag: (code: string | null) => string | null | undefined;
  countryName: (code: string | null) => string | undefined;
}>();

const localePath = useLocalePath();

// v-data-table caches column widths per key on first render and doesn't
// react to width/column-count changes after that -- SSR always guesses xs
// (no real viewport to measure), so once the client corrects `xs` post-
// mount, the table would otherwise keep rendering the wrong (SSR-guessed)
// column layout forever. Force one clean remount right after mount, keyed
// on the now-correct value, to pick up the real widths. Harmless no-op for
// tables that only ever render client-side post-hydration (e.g. search).
const { xs } = useDisplay();
const mounted = ref(false);
onMounted(() => { mounted.value = true; });
const tableKey = computed(() => (mounted.value ? `full-${xs.value}` : "ssr"));
</script>

<template>
  <v-data-table
    :key="tableKey"
    :headers="headers"
    :items="items"
    :loading="loading"
    items-per-page="-1"
    hide-default-footer
    density="compact"
    :no-data-text="noDataText"
  >
    <template #header.country="{ column }">
      <v-icon icon="mdi-flag-outline" size="16" :title="column.title" />
    </template>
    <template #item.name="{ item }">
      <span class="player-cell" :title="item.name">
        <span v-if="item.title" class="player-title-prefix">{{ item.title }}</span>
        <NuxtLink :to="localePath(`/player/${item.fideid}`)" class="player-name-link text-high-emphasis">{{ item.name }}</NuxtLink>
      </span>
    </template>
    <template #item.country="{ item }">
      <span
        v-if="countryFlag(item.country)"
        :class="countryFlag(item.country)"
        :title="countryName(item.country)"
        style="font-size: 1.2em"
      />
      <span v-else :title="item.country ?? undefined">{{ item.country }}</span>
    </template>
    <template v-for="(_, slot) in $slots" #[slot]="scope" :key="slot">
      <slot :name="slot" v-bind="scope ?? {}" />
    </template>
  </v-data-table>
</template>

<style scoped>
/* table-layout: fixed so columns hold their declared widths instead of
   growing to fit content (the name column, with nothing declared, then
   takes whatever's left) -- and cell padding trimmed, compact density's
   default still left visible margin between columns. */
:deep(table) {
  table-layout: fixed;
}
:deep(.v-data-table__td),
:deep(.v-data-table__th) {
  padding-inline: 6px !important;
}
.player-cell {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.player-title-prefix {
  color: #ff8f00; /* amber-darken-2, same as the title chip on the player page */
  font-weight: 700;
  font-size: 0.85em;
  margin-right: 4px;
}
.player-name-link {
  color: rgb(var(--v-theme-primary));
  text-decoration: underline;
  text-decoration-color: transparent;
  transition: text-decoration-color 0.15s;
}
.player-name-link:hover {
  text-decoration-color: currentColor;
}
</style>
