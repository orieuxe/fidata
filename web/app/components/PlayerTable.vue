<script setup lang="ts" generic="T extends { fideid: number; name: string; country: string | null }">
import { useLocalePath } from "#i18n";

defineProps<{
  headers: { title: string; key: string; width?: number }[];
  items: T[];
  loading?: boolean;
  noDataText?: string;
  countryFlag: (code: string | null) => string | null | undefined;
  countryName: (code: string | null) => string | undefined;
}>();

const localePath = useLocalePath();
</script>

<template>
  <v-data-table
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
      <NuxtLink :to="localePath(`/player/${item.fideid}`)" class="player-name-link text-high-emphasis">{{ item.name }}</NuxtLink>
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
.player-name-link {
  text-decoration: none;
}
.player-name-link:hover {
  text-decoration: underline;
}
</style>
