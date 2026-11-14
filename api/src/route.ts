import { randomUUID } from "node:crypto";
import { type Classification, classifyRoute } from "./classify.js";
import type { FusedAccess } from "./fused.js";
import { decodePolyline6 } from "./polyline.js";
import { type TraceEdge, type ValhallaBody, type ValhallaClient, ValhallaError, type ValhallaResponse } from "./valhalla.js";

export type RouteFormat = "valhalla" | "osrm";

export interface Point {
  lat: number;
  lon: number;
}

export interface RouteRequest {
  origin: Point;
  destination: Point;
  verifiedOnly: boolean;
  format: RouteFormat;
  language: string;
}

export interface VerifiedOnlyInfo {
  requests: number;
  excluded_points: number;
  converged: boolean;
  stopped_because?: string;
}

export interface RouteResult {
  response: ValhallaResponse;
  naviscoot: Classification & {
    route_id: string;
    format: RouteFormat;
    verified_only?: VerifiedOnlyInfo;
  };
}

interface Attempt {
  response: ValhallaResponse;
  shape: string;
  edges: TraceEdge[];
  classification: Classification;
}

export interface RouteDeps {
  valhalla: ValhallaClient;
  fused: FusedAccess;
  maxVerifiedRequests: number;
}

export function valhallaBody(req: RouteRequest, exclude: Point[]): ValhallaBody {
  return {
    locations: [req.origin, req.destination].map(({ lat, lon }) => ({ lat, lon })),
    costing: "motor_scooter",
    date_time: { type: 0 },
    directions_options: { units: "kilometers", language: req.language },
    ...(req.format === "osrm" ? { format: "osrm", banner_instructions: true, voice_instructions: true } : {}),
    ...(exclude.length ? { exclude_locations: exclude } : {}),
  };
}

function geometry(response: ValhallaResponse, format: RouteFormat): { shape: string; lengthM: number } {
  if (format === "osrm") {
    const route = (response.routes as { geometry: string; distance: number }[] | undefined)?.[0];
    if (!route) throw new ValhallaError("valhalla returned no route", 502);
    return { shape: route.geometry, lengthM: route.distance };
  }
  const trip = response.trip as { legs: { shape: string }[]; summary: { length: number } } | undefined;
  const leg = trip?.legs[0];
  if (!trip || !leg) throw new ValhallaError("valhalla returned no trip", 502);
  return { shape: leg.shape, lengthM: trip.summary.length * 1000 };
}

async function attempt(deps: RouteDeps, req: RouteRequest, exclude: Point[]): Promise<Attempt> {
  const response = await deps.valhalla.route(valhallaBody(req, exclude));
  const { shape, lengthM } = geometry(response, req.format);
  const edges = await deps.valhalla.edgeWalk(shape);
  return { response, shape, edges, classification: classifyRoute(edges, lengthM, deps.fused) };
}

export function unverifiedMidpoints(a: Attempt): Point[] {
  const coords = decodePolyline6(a.shape);
  const last = a.edges.length - 1;
  const points: Point[] = [];
  for (const stretch of a.classification.stretches) {
    if (stretch.class !== "unverified") continue;
    for (let i = Math.max(stretch.first_edge, 1); i <= Math.min(stretch.last_edge, last - 1); i++) {
      const edge = a.edges[i]!;
      const mid = edge.begin_shape_index + edge.end_shape_index;
      const p = coords[mid >> 1];
      const q = coords[(mid + 1) >> 1];
      if (p && q) points.push({ lat: (p[0] + q[0]) / 2, lon: (p[1] + q[1]) / 2 });
    }
  }
  return points;
}

function markUnavoidable(c: Classification, edgeCount: number): Classification {
  return {
    ...c,
    stretches: c.stretches.map((s) => {
      if (s.class !== "unverified") return s;
      const hasInteriorEdge = Math.max(s.first_edge, 1) <= Math.min(s.last_edge, edgeCount - 2);
      return { ...s, unavoidable: hasInteriorEdge ? "no_alternative" : "endpoint" };
    }),
  };
}

export async function planRoute(deps: RouteDeps, req: RouteRequest): Promise<RouteResult> {
  const routeId = randomUUID();
  let current = await attempt(deps, req, []);
  if (!req.verifiedOnly) {
    return { response: current.response, naviscoot: { ...current.classification, route_id: routeId, format: req.format } };
  }

  let exclude: Point[] = [];
  let requests = 1;
  let converged = false;
  let stoppedBecause: string | undefined;
  for (;;) {
    const midpoints = unverifiedMidpoints(current);
    if (!midpoints.length) {
      converged = true;
      break;
    }
    if (requests >= deps.maxVerifiedRequests) {
      stoppedBecause = `request cap of ${deps.maxVerifiedRequests} reached`;
      break;
    }
    const nextExclude = [...exclude, ...midpoints];
    requests += 1;
    try {
      current = await attempt(deps, req, nextExclude);
      exclude = nextExclude;
    } catch (err) {
      stoppedBecause = (err as Error).message;
      break;
    }
  }

  return {
    response: current.response,
    naviscoot: {
      ...markUnavoidable(current.classification, current.edges.length),
      route_id: routeId,
      format: req.format,
      verified_only: {
        requests,
        excluded_points: exclude.length,
        converged,
        ...(stoppedBecause ? { stopped_because: stoppedBecause } : {}),
      },
    },
  };
}
