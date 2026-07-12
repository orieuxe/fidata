import { useRuntimeConfig } from "#app";

/** Thin wrapper around the PostgREST API (auto-generated from the `ratings` table/view). */
export function useApi() {
  const { public: { apiBase } } = useRuntimeConfig();

  function get<T>(path: string, query?: Record<string, string>) {
    return $fetch<T>(path, { baseURL: apiBase, query });
  }

  return { get };
}
