import re

ALLOWED = "allowed"
FORBIDDEN = "forbidden"
UNKNOWN = "unknown"

MOPED_ALLOWED_VALUES = {"yes", "designated", "permissive", "destination"}
MOPED_FORBIDDEN_VALUES = {"no"}
MOPED_KEYS = ("moped", "moped:forward", "moped:backward")
TRAFFIC_SIGN_KEYS = ("traffic_sign", "traffic_sign:forward", "traffic_sign:backward")

_SIGN_RE = re.compile(r"(?:^|[;,])\s*(?:NL:)?(G11|G12a|G13)(?![0-9A-Za-z])")
SIGN_STATUS = {"G11": FORBIDDEN, "G12a": ALLOWED, "G13": FORBIDDEN}


def signs_in_tags(tags: dict[str, str]) -> set[str]:
    found: set[str] = set()
    for key in TRAFFIC_SIGN_KEYS:
        value = tags.get(key)
        if value:
            found.update(_SIGN_RE.findall(value))
    return found


def moped_tag_status(tags: dict[str, str]) -> str | None:
    values = [tags[k].strip().lower() for k in MOPED_KEYS if k in tags]
    if not values:
        return None
    if any(v in MOPED_ALLOWED_VALUES for v in values):
        return ALLOWED
    if all(v in MOPED_FORBIDDEN_VALUES for v in values):
        return FORBIDDEN
    return None


def sign_tag_status(tags: dict[str, str]) -> str | None:
    statuses = {SIGN_STATUS[s] for s in signs_in_tags(tags)}
    return statuses.pop() if len(statuses) == 1 else None


def osm_status(tags: dict[str, str]) -> tuple[str, str]:
    """Status from OSM alone. `mofa=*` is the snorfiets and is deliberately never consulted."""
    by_moped = moped_tag_status(tags)
    if by_moped is not None:
        return by_moped, "moped tag"
    by_sign = sign_tag_status(tags)
    if by_sign is not None:
        return by_sign, "traffic_sign tag"
    return UNKNOWN, "no moped information"


def tag_sign_disagreement(tags: dict[str, str]) -> bool:
    by_moped = moped_tag_status(tags)
    by_sign = sign_tag_status(tags)
    return by_moped is not None and by_sign is not None and by_moped != by_sign
