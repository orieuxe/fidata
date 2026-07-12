<script setup lang="ts">
import { useTheme } from "vuetify";

const theme = useTheme();
const themeCookie = useCookie<"light" | "dark">("theme", { default: () => "dark" });

function toggleTheme() {
  theme.global.name.value = theme.global.name.value === "dark" ? "light" : "dark";
  themeCookie.value = theme.global.name.value as "light" | "dark";
}
</script>

<template>
  <v-app>
    <NuxtLoadingIndicator color="#1976d2" />
    <v-app-bar title="FIDE Ratings">
      <v-btn to="/" text="Top players" />
      <v-btn to="/active" text="Most active" />
      <v-btn to="/movers" text="Rating movers" />
      <v-btn href="https://lichess.org/fide" target="_blank" rel="noopener" text="Find a player" append-icon="mdi-open-in-new" />
      <v-spacer />
      <v-btn
        :icon="theme.global.current.value.dark ? 'mdi-weather-sunny' : 'mdi-weather-night'"
        @click="toggleTheme"
      />
    </v-app-bar>
    <v-main>
      <NuxtPage />
    </v-main>
  </v-app>
</template>
