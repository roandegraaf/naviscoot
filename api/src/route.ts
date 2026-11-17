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
export const QUIET_TOP_SPEED_KMH = 30;
export const FASTEST_SLACK = { share: 0.1, minS: 30, maxS: 180 };

export function fastestSlackS(quickestS: number): number {
  return Math.min(FASTEST_SLACK.maxS, Math.max(FASTEST_SLACK.minS, quickestS * FASTEST_SLACK.share));
}

export type RouteProfile = "fastest" | "quiet";
export type Costing = Record<string, number | boolean>;

// motor_scooter cost is not time: speed_penalty_factor, road classes, density and turn costs can make the default
// pick a route minutes slower. These are probed while the default is planned; a candidate replaces it only when both
// its probe and its own plan beat the default by more than fastestSlackS(): the price of the smoother default.
// shortest ignores use_ferry, so it sits out when ferries are avoided.
export const FASTEST_CANDIDATES: Costing[] = [
  { speed_penalty_factor: 0 },
  { speed_penalty_factor: 0, use_primary: 1 },
  { shortest: true },
  { speed_penalty_factor: 0, use_primary: 1, use_living_streets: 1, service_penalty: 0 },
];

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
  profile: RouteProfile;
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
  fastestCandidates?: Costing[];
}

type Mode = "primary" | "alternates";

interface Walked {
  raw: Record<string, unknown>;
  legShapes: string[];
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

export function requestedProfile(req: RouteRequest): RouteProfile {
  return req.avoid?.main_roads ? "quiet" : "fastest";
}

// The quiet profile caps the speed the search assumes, so a 50 km/h main road loses its edge over a 30 km/h
// street; use_primary alone cannot outweigh that. Its times are wrong until retime() re-traces the route.
function profileCosting(profile: RouteProfile): Costing {
  return profile === "quiet" ? { use_primary: 0, top_speed: QUIET_TOP_SPEED_KMH } : {};
}

function costingOptions(avoid: Avoid | undefined, costing: Costing): Costing | undefined {
  const options: Costing = { ...(avoid?.ferries ? { use_ferry: 0 } : {}), ...costing };
  return Object.keys(options).length ? options : undefined;
}

export function valhallaBody(
  req: RouteRequest,
  exclude: Point[],
  mode: Mode = "primary",
  now = new Date(),
  costing: Costing = profileCosting(requestedProfile(req)),
): ValhallaBody {
  const stops = (req.waypoints ?? []).map(({ lat, lon }) => ({ lat, lon, type: "break" }));
  const motorScooter = costingOptions(req.avoid, costing);
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
  return { raw: route.raw, legShapes: route.legShapes, coords, edges, legs, classification: classifyRoute(edges, route.lengthM, deps.fused) };
}

async function fetchRound(deps: RouteDeps, req: RouteRequest, mode: Mode, costing: Costing, exclude: Point[], now: Date): Promise<Round> {
  const response = await deps.valhalla.route(valhallaBody(req, exclude, mode, now, costing));
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
  profile: RouteProfile;
  verifiedOnly?: VerifiedOnlyInfo;
  unpaved?: (w: Walked) => AvoidUnpavedInfo;
}

async function refine(
  deps: RouteDeps,
  req: RouteRequest,
  mode: Mode,
  profile: RouteProfile,
  now: Date,
  costing: Costing = profileCosting(profile),
): Promise<Refined> {
  const avoidUnpaved = req.avoid?.unpaved === true;
  let current = await fetchRound(deps, req, mode, costing, [], now);
  if (!req.verifiedOnly && !avoidUnpaved) return { round: current, profile };

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
      current = await fetchRound(deps, req, mode, costing, [...current.exclude, ...points], now);
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
    profile,
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
    profile: refined.profile,
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

type OsrmTraced = Record<string, unknown> & { geometry: string; distance: number; duration: number; weight?: number; legs: unknown[] };
type TripTraced = { legs: Record<string, unknown>[]; summary: Record<string, unknown> & { length: number; time: number } };

function traceBody(req: RouteRequest, shape: string): ValhallaBody {
  return {
    encoded_polyline: shape,
    shape_match: "edge_walk",
    costing: "motor_scooter",
    directions_options: { units: "kilometers", language: req.language },
    ...(req.format === "osrm" ? { format: "osrm", banner_instructions: true, voice_instructions: true } : {}),
  };
}

function osrmMatching(response: ValhallaResponse): OsrmTraced {
  const matchings = response.matchings as OsrmTraced[] | undefined;
  if (matchings?.length !== 1) throw new ClassificationError(`trace_route returned ${matchings?.length ?? 0} matchings`);
  const { confidence: _, ...route } = matchings[0]!;
  return route as OsrmTraced;
}

function stitchOsrm(pieces: OsrmTraced[]): Record<string, unknown> {
  if (pieces.length === 1) return pieces[0]!;
  const points = pieces.flatMap((p, i) => (i === 0 ? decodePolyline6(p.geometry) : decodePolyline6(p.geometry).slice(1)));
  return {
    ...pieces[0]!,
    geometry: encodePolyline6(points),
    legs: pieces.flatMap((p) => p.legs),
    distance: pieces.reduce((sum, p) => sum + p.distance, 0),
    duration: pieces.reduce((sum, p) => sum + p.duration, 0),
    weight: pieces.reduce((sum, p) => sum + (p.weight ?? 0), 0),
  };
}

function stitchTrip(original: TripTraced, pieces: TripTraced[]): Record<string, unknown> {
  const legs = pieces.flatMap((p) => p.legs);
  const summary = {
    ...original.summary,
    length: pieces.reduce((sum, p) => sum + p.summary.length, 0),
    time: pieces.reduce((sum, p) => sum + p.summary.time, 0),
  };
  return { trip: { ...original, legs, summary } };
}

// Re-traces a quiet route leg by leg with the default costing, which keeps its geometry and gives real
// times and instructions. A zero-length leg (the same stop twice) cannot be traced and keeps its own.
async function retime(deps: RouteDeps, req: RouteRequest, w: Walked): Promise<Walked> {
  const lengths = w.legs.map((leg) => w.edges.slice(leg.first_edge, leg.last_edge + 1).reduce((sum, e) => sum + e.length, 0));
  const traced = await Promise.all(
    w.legShapes.map((shape, i) => (lengths[i] === 0 ? Promise.resolve(undefined) : deps.valhalla.traceRoute(traceBody(req, shape)))),
  );
  let raw: Record<string, unknown>;
  if (req.format === "osrm") {
    const original = w.raw as OsrmTraced;
    raw = stitchOsrm(
      traced.map((t, i) =>
        t
          ? osrmMatching(t)
          : { geometry: w.legShapes[i]!, distance: 0, duration: 0, weight: 0, legs: [original.legs[i]] },
      ),
    );
  } else {
    const original = (w.raw as { trip: TripTraced }).trip;
    raw = stitchTrip(
      original,
      traced.map((t, i) =>
        t ? (t.trip as TripTraced) : { legs: [original.legs[i]!], summary: { length: 0, time: 0 } },
      ),
    );
  }
  const response: ValhallaResponse = req.format === "osrm" ? { routes: [raw] } : raw;
  return walk(deps, rawRoutes(response, req.format)[0]!);
}

function probeSeconds(response: ValhallaResponse): number | undefined {
  const time = (response.trip as { summary?: { time?: unknown } } | undefined)?.summary?.time;
  return typeof time === "number" ? time : undefined;
}

function routeSeconds(w: Walked, format: RouteFormat): number | undefined {
  const time =
    format === "osrm"
      ? (w.raw as { duration?: unknown }).duration
      : (w.raw as { trip?: { summary?: { time?: unknown } } }).trip?.summary?.time;
  return typeof time === "number" ? time : undefined;
}

async function quickestCandidate(deps: RouteDeps, req: RouteRequest, now: Date): Promise<{ costing: Costing; seconds: number } | undefined> {
  const candidates = (deps.fastestCandidates ?? []).filter((c) => !(c.shortest && req.avoid?.ferries));
  const times = await Promise.all(
    candidates.map((costing) =>
      deps.valhalla
        .route({ ...valhallaBody({ ...req, format: "valhalla" }, [], "primary", now, costing), directions_type: "none" })
        .then(probeSeconds, () => undefined),
    ),
  );
  let best: { costing: Costing; seconds: number } | undefined;
  times.forEach((seconds, i) => {
    if (seconds !== undefined && (!best || seconds < best.seconds)) best = { costing: candidates[i]!, seconds };
  });
  return best;
}

async function planFastest(deps: RouteDeps, req: RouteRequest, mode: Mode, now: Date): Promise<Refined> {
  if (mode !== "primary" || !deps.fastestCandidates?.length) return refine(deps, req, mode, "fastest", now);
  const [base, quickest] = await Promise.all([refine(deps, req, mode, "fastest", now), quickestCandidate(deps, req, now)]);
  const baseSeconds = routeSeconds(base.round.routes[0]!, req.format);
  if (!quickest || baseSeconds === undefined || baseSeconds - quickest.seconds <= fastestSlackS(quickest.seconds)) return base;
  const other = await optional(refine(deps, req, mode, "fastest", now, quickest.costing));
  const otherSeconds = other && routeSeconds(other.round.routes[0]!, req.format);
  return other && otherSeconds !== undefined && baseSeconds - otherSeconds > fastestSlackS(otherSeconds) ? other : base;
}

async function plan(deps: RouteDeps, req: RouteRequest, mode: Mode, profile: RouteProfile, now: Date): Promise<Refined> {
  if (profile === "fastest") return planFastest(deps, req, mode, now);
  const refined = await refine(deps, req, mode, profile, now);
  const routes = await Promise.all(refined.round.routes.map((w) => retime(deps, req, w)));
  return { ...refined, round: { ...refined.round, routes } };
}

async function optional(work: Promise<Refined>): Promise<Refined | undefined> {
  try {
    return await work;
  } catch (err) {
    if (err instanceof ValhallaError && err.unavailable) throw err;
    return undefined;
  }
}

async function primaryPlan(deps: RouteDeps, req: RouteRequest, now: Date): Promise<Refined> {
  const profile = requestedProfile(req);
  if (profile === "fastest") return plan(deps, req, "primary", "fastest", now);
  return (await optional(plan(deps, req, "primary", "quiet", now))) ?? plan(deps, req, "primary", "fastest", now);
}

function responseFor(base: ValhallaResponse, format: RouteFormat, routes: Walked[], withAlternates: boolean): ValhallaResponse {
  const [main, ...alts] = routes;
  if (format === "osrm") return { ...base, routes: routes.map((w) => w.raw) };
  return { ...base, ...main!.raw, ...(withAlternates ? { alternates: alts.map((w) => w.raw) } : {}) };
}

export async function planRoute(deps: RouteDeps, req: RouteRequest, now = new Date()): Promise<RouteResult> {
  const wanted = Math.min(req.alternatives ?? 0, MAX_ALTERNATIVES);
  const contrastProfile: RouteProfile = requestedProfile(req) === "quiet" ? "fastest" : "quiet";
  const [primary, contrast, extra] = await Promise.all([
    primaryPlan(deps, req, now),
    wanted > 0 ? optional(plan(deps, req, "primary", contrastProfile, now)) : Promise.resolve(undefined),
    wanted > 0 ? optional(refine(deps, req, "alternates", "fastest", now)) : Promise.resolve(undefined),
  ]);
  const main = primary.round.routes[0]!;
  const naviscoot: RouteResult["naviscoot"] = meta(main, primary, req);
  if (!wanted) return { response: responseFor(primary.round.response, req.format, [main], false), naviscoot };

  const kept: Walked[] = [main];
  const alts: { walked: Walked; from: Refined }[] = [];
  const candidates = [
    ...(contrast?.round.routes.slice(0, 1) ?? []).map((walked) => ({ walked, from: contrast! })),
    ...(extra?.round.routes ?? []).map((walked) => ({ walked, from: extra! })),
  ];
  for (const candidate of candidates) {
    if (alts.length >= wanted) break;
    if (kept.some((k) => sharedFraction(candidate.walked, k) >= ALTERNATIVE_MAX_SHARED)) continue;
    kept.push(candidate.walked);
    alts.push(candidate);
  }
  naviscoot.alternates = alts.map((a) => meta(a.walked, a.from, req));
  const response = responseFor(primary.round.response, req.format, [main, ...alts.map((a) => a.walked)], true);
  return { response, naviscoot };
}
