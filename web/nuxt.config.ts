import vuetify from "vite-plugin-vuetify";

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: "2025-07-15",
  devtools: { enabled: true },
  imports: { autoImport: false },
  components: false,
  modules: ["@nuxtjs/i18n"],
  css: ["vuetify/styles", "@mdi/font/css/materialdesignicons.css", "flag-icons/css/flag-icons.min.css", "~/assets/css/fide-flag.css"],
  build: { transpile: ["vuetify"] },
  vite: {
    plugins: [vuetify({ autoImport: true })],
  },
  runtimeConfig: {
    // Server-only: used for SSR fetches from inside the container, where
    // "localhost" would resolve to the container itself instead of the
    // host. Defaults to the public value (single-process/prod setups).
    apiBaseServer: process.env.NUXT_PUBLIC_API_BASE ?? "http://localhost:3001",
    public: {
      apiBase: process.env.NUXT_PUBLIC_API_BASE ?? "http://localhost:3001",
    },
  },
  routeRules: {
    // Too many players to prerender (one DB fetch per fideid, no fixed
    // "default" state) -- fetched client-side like today, just without SSR.
    // `prerender: false` is what actually keeps the generate crawler from
    // following every player link it finds on the list pages.
    "/player/**": { ssr: false, prerender: false },
  },
  i18n: {
    strategy: "prefix_except_default",
    defaultLocale: "en",
    locales: [
      { code: "en", name: "English", file: "en.json" },
      { code: "fr", name: "Français", file: "fr.json" },
      { code: "es", name: "Español", file: "es.json" },
      { code: "de", name: "Deutsch", file: "de.json" },
      { code: "nl", name: "Nederlands", file: "nl.json" },
    ],
    langDir: "locales/",
    detectBrowserLanguage: {
      useCookie: true,
      cookieKey: "locale",
    },
  },
});
