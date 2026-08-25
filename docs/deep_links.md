# Minedart deep links

Minedart reads URL query parameters from `Uri.base`. There is no custom native
URL scheme, Android intent filter, or path router.

## Parameters

- `seed=<value>` creates a fresh generated world. Accepted forms are decimal,
  `0x` hexadecimal, negative `-0x` hexadecimal, and legacy unprefixed hex.
- `preset=classic|flat|islands` selects generation. An unknown value falls
  back to `classic`; when present without `seed`, a fresh signed 32-bit seed is
  generated from the platform cryptographic RNG.
- `world=<safe-local-id>` loads that id from the current native repository or
  browser IndexedDB. IDs are 1-64 ASCII letters, digits, `_` or `-`.

`world` has priority when it resolves. Otherwise any `seed`/`preset` parameter
generates a new world; otherwise the most recently updated readable local world
loads. If no readable local world exists, a new Classic world receives a fresh
random seed. Edited worlds are portable through MDRT2 export/import, not
`world` URLs.

## Examples

```text
https://minedart.castletaste.dev/?seed=0x5eed&preset=classic
https://minedart.castletaste.dev/?seed=42&preset=flat
https://minedart.castletaste.dev/?seed=-0x10&preset=islands
https://minedart.castletaste.dev/?world=world-local_01
```

World Library's Share seed action emits only `seed` and `preset`. The removed
`builder` parameter is intentionally unsupported.
