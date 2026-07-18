import { watch, type Ref } from "vue";
import { useRoute, useRouter } from "#app";

type FilterRefs = Record<string, Ref<unknown>>;

const NUMERIC = /^-?\d+$/;

/**
 * Two-way sync between a page's filter refs and the URL query string --
 * shareable/bookmarkable filter links, back-button support.
 */
export function useUrlFilters(refs: FilterRefs) {
  const route = useRoute();
  const router = useRouter();

  for (const [key, r] of Object.entries(refs)) {
    const raw = route.query[key];
    if (raw == null) continue;
    if (Array.isArray(r.value)) r.value = String(raw).split(",").filter(Boolean);
    // Fields like year/minAge/maxAge/limit are `number | null` refs -- a
    // null default can't be told apart from a string ref by its current
    // value alone, so numeric-looking query values are coerced on sight.
    else r.value = NUMERIC.test(String(raw)) ? Number(raw) : String(raw);
  }

  watch(Object.values(refs), () => {
    const query: Record<string, string> = {};
    for (const [key, r] of Object.entries(refs)) {
      const v = r.value;
      if (v == null || v === "" || (Array.isArray(v) && v.length === 0)) continue;
      query[key] = Array.isArray(v) ? v.join(",") : String(v);
    }
    router.replace({ query });
  });
}
