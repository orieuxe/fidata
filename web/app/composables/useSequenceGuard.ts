// Guards against a stale async response being applied after a newer call
// (e.g. a fast filter change) has superseded it -- shared by every page/
// composable that races a fetch against filter changes.
export function useSequenceGuard() {
  let token = 0;

  function start() {
    return ++token;
  }

  // Snapshot the current token without starting a new generation -- for
  // operations that should be invalidated by a start() elsewhere (e.g. a
  // filter change) but must not themselves invalidate one another.
  function current() {
    return token;
  }

  function isStale(startedAt: number) {
    return startedAt !== token;
  }

  return { start, current, isStale };
}
