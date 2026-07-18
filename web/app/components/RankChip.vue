<script setup lang="ts">
import { useI18n } from "#i18n";
import { formatNumber, formatPercentile } from "~/utils/format";

const props = defineProps<{
  rank: number | null;
  total: number | null;
  scope: "world" | "country";
  countryName?: string | null;
  countryFlagClass?: string | null;
}>();

const { t, locale } = useI18n();
</script>

<template>
  <v-chip
    v-if="rank != null"
    size="small"
    variant="tonal"
    :color="scope === 'world' ? 'primary' : undefined"
    :prepend-icon="scope === 'world' ? 'mdi-earth' : undefined"
    :title="
      scope === 'world'
        ? t('pages.totalActivePlayersWorld', { n: formatNumber(total, locale) })
        : t('pages.totalActivePlayersCountry', { n: formatNumber(total, locale), country: countryName })
    "
  >
    <span v-if="scope === 'country' && countryFlagClass" :class="countryFlagClass" class="mr-1" />
    {{ t("pages.activityChipShort", { rank: formatNumber(rank, locale), p: formatPercentile(rank, total) }) }}
  </v-chip>
</template>
