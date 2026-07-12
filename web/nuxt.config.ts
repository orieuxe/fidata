import vuetify from "vite-plugin-vuetify";

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: "2025-07-15",
  devtools: { enabled: true },
  css: ["vuetify/styles", "@mdi/font/css/materialdesignicons.css"],
  build: { transpile: ["vuetify"] },
  vite: {
    plugins: [vuetify({ autoImport: true })],
  },
  runtimeConfig: {
    public: {
      apiBase: process.env.NUXT_PUBLIC_API_BASE ?? "http://localhost:3001",
    },
  },
});
