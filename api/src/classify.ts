import type { FusedAccess } from "./fused.js";
import type { TraceEdge } from "./valhalla.js";

export const STRETCH_CLASSES = ["carriageway", "moped_path", "unverified", "forbidden"] as const;
export type StretchClass = (typeof STRETCH_CLASSES)[number];

export type UnavoidableReason = "endpoint" | "no_alternative";

export interface Stretch {
  class: StretchClass;
  start_shape_index: number;
  end_shape_index: number;
  first_edge: number;
  last_edge: number;
  length_m: number;
  way_ids: number[];
  unavoidable?: UnavoidableReason;
}

export interface SpeedLimitRun {
  start_shape_index: number;
  end_shape_index: number;
  kmh: number;
}

export interface Classification {
  length_m: number;
  edge_length_m: number;
  totals_m: Record<StretchClass, number>;
  stretches: Stretch[];
  speed_limits: SpeedLimitRun[];
  warnings: string[];
}

export const CARRIAGEWAY_LIMIT_KMH = 45;
export const PATH_LIMITS_KMH = new Set([30, 40]);
export const DEFAULT_PATH_LIMIT_KMH = 30;

const PATH_USES = new Set([
  "cycleway",
  "path",
  "mountain_bike",
  "footway",
  "sidewalk",
  "pedestrian",
  "pedestrian_crossing",
  "bridleway",
]);

const EDGE_MISMATCH_WARNING = 0.005;

export function edgeClass(edge: TraceEdge, fused: FusedAccess): StretchClass {
  switch (fused.get(edge.way_id)) {
    case "unknown":
      return "unverified";
    case "allowed":
      return "moped_path";
    case "forbidden":
      return "forbidden";
    default:
      return PATH_USES.has(edge.use) ? "moped_path" : "carriageway";
  }
}

export function edgeLimitKmh(edge: TraceEdge, cls: StretchClass): number {
  if (cls === "carriageway") return CARRIAGEWAY_LIMIT_KMH;
  return edge.speed_limit !== undefined && PATH_LIMITS_KMH.has(edge.speed_limit) ? edge.speed_limit : DEFAULT_PATH_LIMIT_KMH;
}

export function speedLimits(edges: TraceEdge[], fused: FusedAccess): SpeedLimitRun[] {
  const runs: SpeedLimitRun[] = [];
  for (const edge of edges) {
    const kmh = edgeLimitKmh(edge, edgeClass(edge, fused));
    const current = runs.at(-1);
    if (current && current.kmh === kmh) {
      current.end_shape_index = edge.end_shape_index;
    } else {
      runs.push({ start_shape_index: edge.begin_shape_index, end_shape_index: edge.end_shape_index, kmh });
    }
  }
  return runs;
}

export function classifyRoute(edges: TraceEdge[], routeLengthM: number, fused: FusedAccess): Classification {
  const lengthM = Math.round(routeLengthM);
  const edgeLengthM = edges.reduce((sum, e) => sum + e.length * 1000, 0);
  const scale = edgeLengthM > 0 ? routeLengthM / edgeLengthM : 0;

  const raw: (Omit<Stretch, "length_m"> & { exact: number })[] = [];
  edges.forEach((edge, index) => {
    const cls = edgeClass(edge, fused);
    const exact = edge.length * 1000 * scale;
    const current = raw.at(-1);
    if (current && current.class === cls) {
      current.end_shape_index = edge.end_shape_index;
      current.last_edge = index;
      current.exact += exact;
      if (current.way_ids.at(-1) !== edge.way_id) current.way_ids.push(edge.way_id);
      return;
    }
    raw.push({
      class: cls,
      start_shape_index: edge.begin_shape_index,
      end_shape_index: edge.end_shape_index,
      first_edge: index,
      last_edge: index,
      exact,
      way_ids: [edge.way_id],
    });
  });

  const rounded = roundToTotal(
    raw.map((s) => s.exact),
    raw.length ? lengthM : 0,
  );
  const stretches: Stretch[] = raw.map(({ exact: _, ...s }, i) => ({ ...s, length_m: rounded[i] ?? 0 }));

  const totals = Object.fromEntries(STRETCH_CLASSES.map((c) => [c, 0])) as Record<StretchClass, number>;
  for (const s of stretches) totals[s.class] += s.length_m;

  const warnings: string[] = [];
  const forbidden = stretches.filter((s) => s.class === "forbidden").flatMap((s) => s.way_ids);
  if (forbidden.length) {
    warnings.push(`route uses way(s) the fused data marks forbidden: ${forbidden.join(", ")}; the graph and fused_access.csv have drifted`);
  }
  if (routeLengthM > 0 && Math.abs(edgeLengthM - routeLengthM) / routeLengthM > EDGE_MISMATCH_WARNING) {
    warnings.push(`edge lengths sum to ${Math.round(edgeLengthM)} m but the route is ${lengthM} m`);
  }

  return {
    length_m: lengthM,
    edge_length_m: Math.round(edgeLengthM),
    totals_m: totals,
    stretches,
    speed_limits: speedLimits(edges, fused),
    warnings,
  };
}

export function roundToTotal(values: number[], total: number): number[] {
  const floors = values.map(Math.floor);
  let remainder = total - floors.reduce((a, b) => a + b, 0);
  const order = values.map((v, i) => [v - Math.floor(v), i] as const).sort((a, b) => b[0] - a[0]);
  for (const [, i] of order) {
    if (remainder <= 0) break;
    floors[i]! += 1;
    remainder -= 1;
  }
  return floors;
}
