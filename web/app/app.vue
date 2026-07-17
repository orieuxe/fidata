<script setup lang="ts">
import { ref } from "vue";
import { useTheme, useDisplay } from "vuetify";
import { useCookie } from "#app";
import { useI18n } from "#i18n";

const theme = useTheme();
const themeCookie = useCookie<"light" | "dark">("theme", { default: () => "dark" });

function toggleTheme() {
  theme.global.name.value = theme.global.name.value === "dark" ? "light" : "dark";
  themeCookie.value = theme.global.name.value as "light" | "dark";
}

const { t, locale, locales, setLocale } = useI18n();
const { mobile } = useDisplay();
const drawer = ref(false);

const navLinks = [
  { to: "/", key: "topPlayers" },
  { to: "/active", key: "mostActive" },
  { to: "/movers", key: "ratingMovers" },
  { to: "/search", key: "findPlayer" },
] as const;
</script>

<template>
  <v-app>
    <NuxtLoadingIndicator color="#1976d2" />
    <v-app-bar :title="t('app.title')">
      <template v-if="mobile" #prepend>
        <v-app-bar-nav-icon @click="drawer = !drawer" />
      </template>
      <template v-if="!mobile">
        <v-btn v-for="l in navLinks" :key="l.to" :to="l.to" :text="t(`nav.${l.key}`)" />
      </template>
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
    <v-navigation-drawer v-if="mobile" v-model="drawer" temporary>
      <v-list>
        <v-list-item
          v-for="l in navLinks"
          :key="l.to"
          :to="l.to"
          :title="t(`nav.${l.key}`)"
          @click="drawer = false"
        />
      </v-list>
    </v-navigation-drawer>
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
