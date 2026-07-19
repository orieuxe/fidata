import { computed } from "vue";
import { useAsyncData } from "#app";
import { useI18n } from "#i18n";
import type { Country } from "~/types/api";
import { useApi } from "./useApi";
import { countryName, flagClass } from "~/utils/countryDisplay";
import { TITLE_OPTIONS } from "~/utils/filterOptions";

// FIDE titles (GM/IM/...) are universal acronyms, left as-is; only the
// synthetic "UNTITLED" option is actual language to translate.
export function useTitleOptions() {
  const { t } = useI18n();
  return computed(() =>
    TITLE_OPTIONS.map((value) => ({ title: value === "UNTITLED" ? t("filters.untitled") : value, value })),
  );
}

export function useYearOptions(includeAllTime: boolean, includeLast12 = false) {
  const { t } = useI18n();
  const currentYear = new Date().getFullYear();
  const years = Array.from({ length: currentYear - 2001 + 1 }, (_, i) => currentYear - i);
  const yearOptions = [
    ...(includeLast12 ? [{ title: t("filters.last12Months"), value: "last12" as const }] : []),
    ...(includeAllTime ? [{ title: t("filters.allTime"), value: null }] : []),
    ...years.map((y) => ({ title: String(y), value: y })),
  ];
  const defaultYear = includeLast12 ? ("last12" as const) : currentYear;
  return { currentYear, defaultYear, yearOptions };
}

export function useRatingTypeOptions(includeAllTimeControls: boolean) {
  const { t } = useI18n();
  return computed(() => [
    ...(includeAllTimeControls ? [{ title: t("filters.allTimeControls"), value: null }] : []),
    { title: t("filters.standard"), value: "standard" },
    { title: t("filters.rapid"), value: "rapid" },
    { title: t("filters.blitz"), value: "blitz" },
  ]);
}

export function useSexOptions() {
  const { t } = useI18n();
  return computed(() => [
    { title: t("filters.male"), value: "M" },
    { title: t("filters.female"), value: "F" },
  ]);
}

export async function useCountryOptions() {
  const { get } = useApi();
  const { t, locale } = useI18n();

  const { data: countries } = await useAsyncData<Country[]>("countries", () =>
    get<Country[]>("/countries"),
  );

  const byCode = computed(() => new Map((countries.value ?? []).map((c) => [c.code, c])));

  function resolveName(code: string) {
    return countryName(byCode.value.get(code), locale.value);
  }

  function nameFor(code: string | null) {
    return code ? resolveName(code) : undefined;
  }

  function flagFor(code: string | null) {
    if (code === "FID") return "fi fi-fide";
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
      .map((c) => ({ title: resolveName(c.code), value: c.code }))
      .sort((a, b) => a.title.localeCompare(b.title, locale.value));
    return [
      { title: t("filters.allCountries"), value: null },
      ...(pinned && codes.some((c) => c.code === pinned) ? [{ title: resolveName(pinned), value: pinned }] : []),
      ...rest,
    ];
  });

  return { countryOptions, countryName: nameFor, countryFlag: flagFor };
}

// Name/country columns are identical across every player table; each page
// appends whatever else it shows (rating, games, delta...). No rank column
// (row order already conveys it) and no title column (it renders inline
// before the name instead, see each page's #item.name).
export function useBaseHeaders() {
  const { t } = useI18n();
  return computed(() => [
    { title: t("table.name"), key: "name" },
    { title: t("table.country"), key: "country" },
  ]);
}
