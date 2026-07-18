# TODO

- Rating distribution with percentile, sliceable by country / worldwide /
  per title.
- Male/female filter (`ratings.sex` already scraped, not exposed as a
  filter anywhere yet).
- 'ans' trad sometimes should be age, maybe set up two trad
- align search page with revamp from other pages
- 

## Frontend: SSG migration

- i18n: switch `no_prefix` -> `prefix_except_default` in
  `web/nuxt.config.ts` (locale in URL, prerequisite for per-language SSG).
- Switch to `nuxt generate`: prerender each page's default (no-filter)
  state per language; filtered data stays client-fetched as today.
- Regenerate the static site after each scraper run (`deploy/` systemd
  timer) so prerendered data doesn't go stale.
- Sync page filters (year, country, rating type, titles, age range, limit,
  direction, name search) to URL query params -- shareable/bookmarkable
  links, back-button support. Query strings are ignored by static file
  serving, so this doesn't blow up the SSG page count.
