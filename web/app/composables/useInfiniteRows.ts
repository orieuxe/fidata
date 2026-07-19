import { ref } from "vue";

// Infinite-scroll pagination shared by search/active/movers: each page hands
// in its own fetchPage(offset, limit) built from its own filters, this just
// tracks the accumulated rows and the v-infinite-scroll load state.
export function useInfiniteRows<T>(
  fetchPage: (offset: number, limit: number) => Promise<T[]>,
  // Getter, not a plain number: active/movers' page size is a reactive
  // "limit" filter that can change after mount.
  pageSize: () => number,
) {
  const rows = ref<T[]>([]);
  const offset = ref(0);
  const finished = ref(false);
  const pending = ref(false);

  // ponytail: plain sequence token instead of AbortController -- infinite
  // scroll's own onLoad already serializes chunk fetches, this only guards
  // against a filter change racing an in-flight one.
  let requestToken = 0;

  async function loadInitial() {
    const token = ++requestToken;
    pending.value = true;
    const data = await fetchPage(0, pageSize());
    if (token !== requestToken) return;
    rows.value = data;
    offset.value = data.length;
    finished.value = data.length < pageSize();
    pending.value = false;
  }

  async function onLoad({ done }: { done: (status: "ok" | "error" | "empty") => void }) {
    if (finished.value) {
      done("empty");
      return;
    }
    const token = requestToken;
    try {
      const data = await fetchPage(offset.value, pageSize());
      if (token !== requestToken) {
        done("ok");
        return;
      }
      rows.value = [...rows.value, ...data];
      offset.value += data.length;
      if (data.length < pageSize()) finished.value = true;
      done(data.length ? "ok" : "empty");
    } catch {
      done("error");
    }
  }

  return { rows, pending, loadInitial, onLoad };
}
