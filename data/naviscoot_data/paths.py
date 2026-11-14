import os
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = DATA_DIR.parent
RAW_DIR = DATA_DIR / "raw"
BUILD_DIR = DATA_DIR / "build"
AUDIT_DOCS_DIR = REPO_DIR / "docs" / "audit"

OSM_COUNTRY_PBF = RAW_DIR / "netherlands-latest.osm.pbf"
OSM_REGION_PBF = BUILD_DIR / "region.osm.pbf"
NDW_RAW_DIR = RAW_DIR / "ndw"
NDW_REGION_GEOJSON = BUILD_DIR / "ndw_region.geojson"
OVERRIDES_CSV = DATA_DIR / "overrides.csv"
FUSED_ACCESS_CSV = Path(os.environ.get("FUSED_ACCESS_CSV", BUILD_DIR / "fused_access.csv")).resolve()
ROUTABLE_PBF = Path(os.environ.get("ROUTABLE_PBF", BUILD_DIR / "routable.osm.pbf")).resolve()
SERVED_GRAPH_DIR = REPO_DIR / "routing" / "build" / "nl"
SERVED_FUSED_CSV = SERVED_GRAPH_DIR / "fused_access.csv"
REGRESSION_CASES = Path(os.environ.get("REGRESSION_CASES", REPO_DIR / "routing" / "regression_cases.json")).resolve()
