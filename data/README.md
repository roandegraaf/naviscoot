# data

Python pipeline that builds the bromfiets access dataset. Requires Python 3.13 and
[uv](https://docs.astral.sh/uv/); `uv` installs the dependencies (pyosmium, requests) on first run.

## Commands

```sh
cd data
uv run fetch     # download and clip all sources
uv run audit     # fuse OSM, NDW and overrides; write build/fused_access.csv and docs/audit/*
uv run rewrite   # write the fused classes into build/routable.osm.pbf for the Valhalla build (~6 min)
uv run pytest    # unit tests (no downloaded data needed)
uv run pytest -m docker     # build the synthetic routing/test fixture with stock and patched graph.lua
uv run pytest -m valhalla   # regression routes against the local NL Valhalla (routing/serve.sh start)
```

`uv run audit` (about 45 s) writes:

- `build/fused_access.csv`: one row per cycle path in the region with the fused bromfiets status
  (`allowed`, `forbidden`, `unknown`), the deciding source (`override`, `ndw_newer`, `osm`, `ndw_sign`, `ndw_propagated`),
  its id (override line, `way/{id}/v{version}` or NDW sign id) and its date.
- `docs/audit/coverage.md`: unknown length before and after fusion, sign attachment and override figures.
- `docs/audit/conflicts.md`: every way where OSM and NDW (or an override) disagree, with both dates.
- `docs/audit/map.html`: inspection map with separate layers for direct and propagated NDW statuses.

## Override list

`overrides.csv` (way id, status, reason, date) beats every other source. Status is `allowed` or `forbidden`;
anything else stops the audit. Say in the reason whether the entry was surveyed. Rows in `conflicts.md`
marked "NDW newer" are the usual candidates.

`uv run fetch` is safe to run repeatedly:

- **OSM**: the Geofabrik Netherlands extract is requested with `If-None-Match` / `If-Modified-Since`;
  an unchanged file is not downloaded again (HTTP 304).
- **Clip**: `build/region.osm.pbf` (50 km around Amersfoort) is rebuilt only when the source file or
  the region parameters change. Ways touching the region are kept whole.
- **NDW**: signs G11, G12a, G12b and G13 come from the verkeersborden API v5, one request per code.
  The API sends no ETag or Last-Modified, so a copy younger than 20 hours is reused instead.
  Each response is checked: it must contain only the requested code and stay under 200 MB
  (the API silently ignores unknown parameters and would return the 1.1 GB national dump;
  G11, the largest, is about 62 MB).
  The bulk files on opendata.ndw.nu are not used because they lack `lastModifiedOn`.

`uv run fetch --force` re-downloads everything.

## Paths and the served graph

`build/fused_access.csv` and `build/routable.osm.pbf` are working files. The env vars `FUSED_ACCESS_CSV` and
`ROUTABLE_PBF` redirect them; `routing/refresh.sh` uses that to write a staged build. The CSV that belongs to the
served graph is `routing/build/nl/fused_access.csv`, and that is what the API and `uv run pytest -m valhalla` read
by default (`REGRESSION_CASES` swaps the cases file). For the whole chain, see "Refresh" in `routing/README.md`.

## Layout

- `raw/` downloads (gitignored)
- `build/` generated data (gitignored)
- `naviscoot_data/` pipeline code (`fuse.py` holds attachment, propagation and precedence)
- `tests/` unit tests, fixture tests (`-m docker`) and the routing regression suite (`-m valhalla`)
- `overrides.csv` hand-maintained override list

See `routing/README.md` for the rewrite rules, the Valhalla build and the regression cases.
