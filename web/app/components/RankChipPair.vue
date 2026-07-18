<script setup lang="ts">
import RankChip from "./RankChip.vue";

defineProps<{
  rankWorld: number | null;
  totalWorld: number | null;
  rankCountry: number | null;
  totalCountry: number | null;
  countryName?: string | null;
  countryFlagClass?: string | null;
}>();
</script>

<template>
  <div class="d-flex flex-wrap justify-center" style="gap: 4px">
    <RankChip scope="world" :rank="rankWorld" :total="totalWorld" />
    <RankChip scope="country" :rank="rankCountry" :total="totalCountry" :country-name="countryName" :country-flag-class="countryFlagClass" />
  </div>
</template>
