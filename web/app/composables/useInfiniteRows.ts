import { ref } from "vue";

export function useInfiniteRows<T>(
  fetchPage: (offset: number, limit: number) => Promise<T[]>,
  pageSize: () => number, // getter: active/movers' limit filter can change after mount
) {
  const rows = ref<T[]>([]);
  const offset = ref(0);
  const finished = ref(false);
  const pending = ref(false);

  // ponytail: sequence token guards a filter change racing an in-flight fetch
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
      rows.value = [...rows.value, ...data] as any;
      offset.value += data.length;
      if (data.length < pageSize()) finished.value = true;
      done(data.length ? "ok" : "empty");
    } catch {
      done("error");
    }
  }

  return { rows, pending, loadInitial, onLoad };
}
