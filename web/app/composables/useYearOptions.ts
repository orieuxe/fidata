import { useI18n } from "#i18n";

export function useYearOptions(includeAllTime: boolean) {
  const { t } = useI18n();
  const currentYear = new Date().getFullYear();
  const count = currentYear - 2015 + 1 + (includeAllTime ? 1 : 0);
  const years = Array.from(
    { length: count },
    (_, i) => (includeAllTime ? currentYear + 1 : currentYear) - i,
  );
  const yearOptions = years.map((y) =>
    includeAllTime && y > currentYear
      ? { title: t("filters.allTime"), value: null }
      : { title: String(y), value: y },
  );
  return { currentYear, yearOptions };
}
