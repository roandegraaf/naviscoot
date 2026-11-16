import { randomUUID } from "node:crypto";
import { type Classification, classifyRoute } from "./classify.js";
import type { FusedAccess } from "./fused.js";
import { decodePolyline6, encodePolyline6, type LatLon } from "./polyline.js";
import { type TraceEdge, type ValhallaBody, type ValhallaClient, ValhallaError, type ValhallaResponse } from "./valhalla.js";

export type RouteFormat = "valhalla" | "osrm";

export interface Point {
  lat: number;
  lon: number;
}

export interface Avoid {
  ferries?: boolean;
  unpaved?: boolean;
  main_roads?: boolean;
}

export interface RouteTime {
  kind: "depart_at" | "arrive_by";
  at: Date;
}

export interface RouteRequest {
  origin: Point;
  destination: Point;
  waypoints?: Point[];
  verifiedOnly: boolean;
  format: RouteFormat;
  language: string;
  alternatives?: number;
  time?: RouteTime;
  avoid?: Avoid;
}

export const MAX_WAYPOINTS = 8;
export const MAX_ALTERNATIVES = 2;
export const VALHALLA_TIME_ZONE = "Europe/Amsterdam";
export const ALTERNATIVE_MAX_SHARED = 0.9;

export interface VerifiedOnlyInfo {
  requests: number;
  excluded_points: number;
  converged: boolean;
  stopped_because?: string;
}

export interface AvoidUnpavedInfo {
  converged: boolean;
  remaining_m: number;
}

export interface LegRange {
  start_shape_index: number;
  end_shape_index: number;
  first_edge: number;
  last_edge: number;
}

export type RouteMeta = Classification & {
  route_id: string;
  format: RouteFormat;
  verified_only?: VerifiedOnlyInfo;
  avoid_unpaved?: AvoidUnpavedInfo;
  legs?: LegRange[];
};

export interface RouteResult {
  response: ValhallaResponse;
  naviscoot: RouteMeta & { alternates?: RouteMeta[] };
}

export interface RouteDeps {
  valhalla: ValhallaClient;
  fused: FusedAccess;
  maxVerifiedRequests: number;
}

type Mode = "primary" | "alternates";

interface Walked {
  raw: Record<string, unknown>;
  coords: LatLon[];
  edges: TraceEdge[];
  legs: LegRange[];
  classification: Classification;
}

interface Round {
  response: ValhallaResponse;
  routes: Walked[];
  exclude: Point[];
}

export function valhallaLocalTime(at: Date): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: VALHALLA_TIME_ZONE,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(at)
      .map((p) => [p.type, p.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

function dateTime(req: RouteRequest, mode: Mode, now: Date): Record<string, unknown> {
  if (mode === "alternates") return { type: 3, value: valhallaLocalTime(req.time?.at ?? now) };
  if (!req.time) return { type: 0 };
  return { type: req.time.kind === "depart_at" ? 1 : 2, value: valhallaLocalTime(req.time.at) };
}

function costingOptions(avoid: Avoid | undefined): Record<string, number> | undefined {
  const options: Record<string, number> = {};
  if (avoid?.ferries) options.use_ferry = 0;
  if (avoid?.main_roads) options.use_primary = 0;
  return Object.keys(options).length ? options : undefined;
}

export function valhallaBody(req: RouteRequest, exclude: Point[], mode: Mode = "primary", now = new Date()): ValhallaBody {
  const stops = (req.waypoints ?? []).map(({ lat, lon }) => ({ lat, lon, type: "break" }));
  const motorScooter = costingOptions(req.avoid);
  return {
    locations: [{ lat: req.origin.lat, lon: req.origin.lon }, ...stops, { lat: req.destination.lat, lon: req.destination.lon }],
    costing: "motor_scooter",
    ...(motorScooter ? { costing_options: { motor_scooter: motorScooter } } : {}),
    date_time: dateTime(req, mode, now),
    ...(mode === "alternates" ? { alternates: MAX_ALTERNATIVES } : {}),
    directions_options: { units: "kilometers", language: req.language },
    ...(req.format === "osrm" ? { format: "osrm", banner_instructions: true, voice_instructions: true } : {}),
    ...(exclude.length ? { exclude_locations: exclude } : {}),
  };
}

export class ClassificationError extends Error {}

interface RawRoute {
  raw: Record<string, unknown>;
  legShapes: string[];
  legLengths: number[];
  lengthM: number;
}

interface OsrmRoute {
  geometry: string;
  distance: number;
  legs?: { distance?: number; steps?: { geometry: string }[] }[];
}

function osrmLegShapes(route: OsrmRoute): string[] {
  const legs = route.legs ?? [];
  if (legs.length <= 1) return [route.geometry];
  const shapes = legs.map((leg) => {
    const steps = (leg.steps ?? []).slice(0, -1).map((step) => decodePolyline6(step.geometry));
    return encodePolyline6(steps.flatMap((points, i) => (i === 0 ? points : points.slice(1))));
  });
  const covered = shapes.reduce((sum, shape) => sum + decodePolyline6(shape).length - 1, 1);
  const total = decodePolyline6(route.geometry).length;
  if (covered !== total) {
    throw new ClassificationError(`leg steps cover ${covered} of ${total} geometry points`);
  }
  return shapes;
}

function rawRoutes(response: ValhallaResponse, format: RouteFormat): RawRoute[] {
  if (format === "osrm") {
    const routes = (response.routes as OsrmRoute[] | undefined) ?? [];
    if (!routes.length) throw new ValhallaError("valhalla returned no route", 502);
    return routes.map((route) => ({
      raw: route as unknown as Record<string, unknown>,
      legShapes: osrmLegShapes(route),
      legLengths: (route.legs ?? [{ distance: route.distance }]).map((l) => l.distance ?? route.distance),
      lengthM: route.distance,
    }));
  }
  type Trip = { legs: { shape: string; summary?: { length: number } }[]; summary: { length: number } };
  const trip = response.trip as Trip | undefined;
  if (!trip?.legs.length) throw new ValhallaError("valhalla returned no trip", 502);
  const alternates = ((response.alternates as { trip: Trip }[] | undefined) ?? []).map((a) => a.trip);
  return [trip, ...alternates].map((t) => ({
    raw: { trip: t },
    legShapes: t.legs.map((l) => l.shape),
    legLengths: t.legs.map((l) => (l.summary?.length ?? t.summary.length) * 1000),
    lengthM: t.summary.length * 1000,
  }));
}

async function walk(deps: RouteDeps, route: RawRoute): Promise<Walked> {
  let legEdges: TraceEdge[][];
  try {
    legEdges = await Promise.all(
      route.legShapes.map((shape, i) => (route.legLengths[i] === 0 ? Promise.resolve([]) : deps.valhalla.edgeWalk(shape))),
    );
  } catch (err) {
    throw new ClassificationError(`route found but edge walk failed: ${(err as Error).message}`);
  }
  const coords: LatLon[] = [];
  const edges: TraceEdge[] = [];
  const legs: LegRange[] = [];
  route.legShapes.forEach((shape, i) => {
    const legCoords = decodePolyline6(shape);
    const offset = Math.max(coords.length - 1, 0);
    coords.push(...(coords.length ? legCoords.slice(1) : legCoords));
    const walked = legEdges[i] ?? [];
    legs.push({
      start_shape_index: offset,
      end_shape_index: offset + legCoords.length - 1,
      first_edge: edges.length,
      last_edge: edges.length + walked.length - 1,
    });
    for (const e of walked) {
      edges.push({ ...e, begin_shape_index: e.begin_shape_index + offset, end_shape_index: e.end_shape_index + offset });
    }
  });
  return { raw: route.raw, coords, edges, legs, classification: classifyRoute(edges, route.lengthM, deps.fused) };
}

async function fetchRound(deps: RouteDeps, req: RouteRequest, mode: Mode, exclude: Point[], now: Date): Promise<Round> {
  const response = await deps.valhalla.route(valhallaBody(req, exclude, mode, now));
  const routes = await Promise.all(rawRoutes(response, req.format).map((r) => walk(deps, r)));
  return { response, routes, exclude };
}

function isLegEnd(w: Walked, edge: number): boolean {
  return w.legs.some((leg) => edge === leg.first_edge || edge === leg.last_edge);
}

function edgeMidpoint(w: Walked, edge: TraceEdge): Point | undefined {
  const mid = edge.begin_shape_index + edge.end_shape_index;
  const p = w.coords[mid >> 1];
  const q = w.coords[(mid + 1) >> 1];
  return p && q ? { lat: (p[0] + q[0]) / 2, lon: (p[1] + q[1]) / 2 } : undefined;
}

export function unverifiedMidpoints(w: Walked): Point[] {
  const points: Point[] = [];
  for (const stretch of w.classification.stretches) {
    if (stretch.class !== "unverified") continue;
    for (let i = stretch.first_edge; i <= stretch.last_edge; i++) {
      if (isLegEnd(w, i)) continue;
      const p = edgeMidpoint(w, w.edges[i]!);
      if (p) points.push(p);
    }
  }
  return points;
}

function interiorUnpavedEdges(w: Walked): TraceEdge[] {
  return w.legs.flatMap((leg) => {
    let first = leg.first_edge;
    let last = leg.last_edge;
    while (first <= last && w.edges[first]?.unpaved) first++;
    while (last >= first && w.edges[last]?.unpaved) last--;
    return w.edges.slice(first, last + 1).filter((e) => e.unpaved);
  });
}

function unpavedMidpoints(w: Walked): Point[] {
  return interiorUnpavedEdges(w).flatMap((e) => edgeMidpoint(w, e) ?? []);
}

function markUnavoidable(w: Walked): Classification {
  const c = w.classification;
  return {
    ...c,
    stretches: c.stretches.map((s) => {
      if (s.class !== "unverified") return s;
      let interior = false;
      for (let i = s.first_edge; i <= s.last_edge && !interior; i++) interior = !isLegEnd(w, i);
      return { ...s, unavoidable: interior ? "no_alternative" : "endpoint" };
    }),
  };
}

interface Refined {
  round: Round;
  verifiedOnly?: VerifiedOnlyInfo;
  unpaved?: (w: Walked) => AvoidUnpavedInfo;
}

async function refine(deps: RouteDeps, req: RouteRequest, mode: Mode, now: Date): Promise<Refined> {
  const avoidUnpaved = req.avoid?.unpaved === true;
  let current = await fetchRound(deps, req, mode, [], now);
  if (!req.verifiedOnly && !avoidUnpaved) return { round: current };

  const verifiedClean = (r: Round) => !req.verifiedOnly || r.routes.every((w) => !unverifiedMidpoints(w).length);
  let lastClean = verifiedClean(current) ? current : undefined;
  let requests = 1;
  let stoppedBecause: string | undefined;
  for (;;) {
    const unverified = req.verifiedOnly ? current.routes.flatMap(unverifiedMidpoints) : [];
    const points = unverified.length || !avoidUnpaved ? unverified : current.routes.flatMap(unpavedMidpoints);
    if (!points.length) break;
    if (requests >= deps.maxVerifiedRequests) {
      stoppedBecause = `request cap of ${deps.maxVerifiedRequests} reached`;
      break;
    }
    requests += 1;
    try {
      current = await fetchRound(deps, req, mode, [...current.exclude, ...points], now);
      if (verifiedClean(current)) lastClean = current;
    } catch (err) {
      stoppedBecause = (err as Error).message;
      break;
    }
  }

  const round = verifiedClean(current) ? current : (lastClean ?? current);
  const converged = verifiedClean(round);
  return {
    round,
    ...(req.verifiedOnly
      ? {
          verifiedOnly: {
            requests,
            excluded_points: round.exclude.length,
            converged,
            ...(!converged && stoppedBecause ? { stopped_because: stoppedBecause } : {}),
          },
        }
      : {}),
    ...(avoidUnpaved
      ? {
          unpaved: (w: Walked) => {
            const remaining = interiorUnpavedEdges(w).reduce((sum, e) => sum + e.length * 1000, 0);
            return { converged: remaining === 0, remaining_m: Math.round(remaining) };
          },
        }
      : {}),
  };
}

function meta(w: Walked, refined: Refined, req: RouteRequest): RouteMeta {
  return {
    ...(req.verifiedOnly ? markUnavoidable(w) : w.classification),
    route_id: randomUUID(),
    format: req.format,
    ...(refined.verifiedOnly ? { verified_only: refined.verifiedOnly } : {}),
    ...(refined.unpaved ? { avoid_unpaved: refined.unpaved(w) } : {}),
    ...(w.legs.length > 1 ? { legs: w.legs } : {}),
  };
}

function wayLengths(w: Walked): Map<number, number> {
  const ways = new Map<number, number>();
  for (const e of w.edges) ways.set(e.way_id, (ways.get(e.way_id) ?? 0) + e.length);
  return ways;
}

export function sharedFraction(candidate: Walked, other: Walked): number {
  const ways = wayLengths(other);
  const total = candidate.edges.reduce((sum, e) => sum + e.length, 0);
  const shared = candidate.edges.reduce((sum, e) => sum + (ways.has(e.way_id) ? e.length : 0), 0);
  return total > 0 ? shared / total : 1;
}

async function alternatives(deps: RouteDeps, req: RouteRequest, now: Date): Promise<Refined | undefined> {
  try {
    return await refine(deps, req, "alternates", now);
  } catch (err) {
    if (err instanceof ValhallaError && err.unavailable) throw err;
    return undefined;
  }
}

export async function planRoute(deps: RouteDeps, req: RouteRequest, now = new Date()): Promise<RouteResult> {
  const wanted = Math.min(req.alternatives ?? 0, MAX_ALTERNATIVES);
  const [primary, extra] = await Promise.all([
    refine(deps, req, "primary", now),
    wanted > 0 ? alternatives(deps, req, now) : Promise.resolve(undefined),
  ]);
  const main = primary.round.routes[0]!;
  const naviscoot: RouteResult["naviscoot"] = meta(main, primary, req);
  if (!wanted) return { response: primary.round.response, naviscoot };

  const kept: Walked[] = [main];
  const alts: Walked[] = [];
  for (const candidate of extra?.round.routes ?? []) {
    if (alts.length >= wanted) break;
    if (kept.some((k) => sharedFraction(candidate, k) >= ALTERNATIVE_MAX_SHARED)) continue;
    kept.push(candidate);
    alts.push(candidate);
  }
  naviscoot.alternates = alts.map((w) => meta(w, extra!, req));

  const response: ValhallaResponse =
    req.format === "osrm"
      ? { ...primary.round.response, routes: [main.raw, ...alts.map((w) => w.raw)] }
      : { ...primary.round.response, alternates: alts.map((w) => w.raw) };
  return { response, naviscoot };
}
