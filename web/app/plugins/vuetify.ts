import { createVuetify } from "vuetify";
import { defineNuxtPlugin, useCookie } from "#app";

export default defineNuxtPlugin((app) => {
  const themeCookie = useCookie<"light" | "dark">("theme", { default: () => "dark" });
  const vuetify = createVuetify({
    theme: { defaultTheme: themeCookie.value },
  });
  app.vueApp.use(vuetify);
});
