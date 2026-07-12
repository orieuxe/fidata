import { computed } from "vue";
import { useAsyncData } from "#app";
import { useI18n } from "#i18n";
import type { Country } from "~/types/api";
import { useApi } from "./useApi";
import { countryName, flagClass } from "~/utils/countryDisplay";

export async function useCountryOptions() {
  const { get } = useApi();
  const { t, locale } = useI18n();

  const { data: countries } = await useAsyncData("countries", () =>
    get<Country[]>("/countries"),
  );

  const byCode = computed(() => new Map((countries.value ?? []).map((c) => [c.code, c])));

  function nameFor(code: string) {
    return countryName(byCode.value.get(code), locale.value);
  }

  function flagFor(code: string | null) {
    return code ? flagClass(byCode.value.get(code)?.iso2) : null;
  }

  const countryOptions = computed(() => {
    const codes = countries.value ?? [];
    // Pin the current locale's own country to the top, found via its ISO
    // alpha-2 region (native Intl.Locale) matched against the iso2 already
    // stored per FIDE code in the DB -- no hardcoded locale->country table.
    const region = new Intl.Locale(locale.value).maximize().region;
    const pinned = codes.find((c) => c.iso2 === region)?.code ?? null;
    const rest = codes
      .filter((c) => c.code !== pinned)
      .map((c) => ({ title: nameFor(c.code), value: c.code }))
      .sort((a, b) => a.title.localeCompare(b.title, locale.value));
    return [
      { title: t("filters.allCountries"), value: null },
      ...(pinned && codes.some((c) => c.code === pinned) ? [{ title: nameFor(pinned), value: pinned }] : []),
      ...rest,
    ];
  });

  return { countryOptions, countryName: nameFor, countryFlag: flagFor };
}
