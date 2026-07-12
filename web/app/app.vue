<script setup lang="ts">
import { useTheme } from "vuetify";
import { useCookie } from "#app";
import { useI18n } from "#i18n";

const theme = useTheme();
const themeCookie = useCookie<"light" | "dark">("theme", { default: () => "dark" });

function toggleTheme() {
  theme.global.name.value = theme.global.name.value === "dark" ? "light" : "dark";
  themeCookie.value = theme.global.name.value as "light" | "dark";
}

const { t, locale, locales, setLocale } = useI18n();
</script>

<template>
  <v-app>
    <NuxtLoadingIndicator color="#1976d2" />
    <v-app-bar :title="t('app.title')">
      <v-btn to="/" :text="t('nav.topPlayers')" />
      <v-btn to="/active" :text="t('nav.mostActive')" />
      <v-btn to="/movers" :text="t('nav.ratingMovers')" />
      <v-btn href="https://lichess.org/fide" target="_blank" rel="noopener" :text="t('nav.findPlayer')" append-icon="mdi-open-in-new" />
      <v-spacer />
      <v-menu>
        <template #activator="{ props }">
          <v-btn icon="mdi-translate" v-bind="props" />
        </template>
        <v-list>
          <v-list-item
            v-for="l in locales"
            :key="l.code"
            :active="l.code === locale"
            :title="l.name"
            @click="setLocale(l.code)"
          />
        </v-list>
      </v-menu>
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

<style>
/* native number spinner misaligns in dense Vuetify fields, drop it */
input[type="number"] {
  -moz-appearance: textfield;
}
input[type="number"]::-webkit-outer-spin-button,
input[type="number"]::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}
</style>
