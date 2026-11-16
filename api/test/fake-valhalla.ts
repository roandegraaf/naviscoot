import { type LatLon, encodePolyline6 } from "../src/polyline.js";
import type { TraceEdge, ValhallaBody, ValhallaClient, ValhallaResponse } from "../src/valhalla.js";

export interface FakeEdge {
  way_id: number;
  use?: string;
  km: number;
  speed_limit?: number;
  unpaved?: boolean;
}

export interface FakeLeg {
  shape: string;
  coords: LatLon[];
  edges: TraceEdge[];
}

export interface FakeRoute extends FakeLeg {
  legs: FakeLeg[];
  lengthKm: number;
}

function fakeLeg(edges: FakeEdge[], start: LatLon, step: number): FakeLeg {
  const coords: LatLon[] = [start];
  const trace: TraceEdge[] = edges.map((e, i) => {
    coords.push([start[0] + (i + 1) * step, start[1] + (i + 1) * step]);
    return {
      way_id: e.way_id,
      length: e.km,
      use: e.use ?? "road",
      begin_shape_index: i,
      end_shape_index: i + 1,
      ...(e.speed_limit === undefined ? {} : { speed_limit: e.speed_limit }),
      ...(e.unpaved ? { unpaved: true } : {}),
    };
  });
  return { shape: encodePolyline6(coords), coords, edges: trace };
}

export function fakeLegs(legs: FakeEdge[][], { step = 0.001, lengthKm }: { step?: number; lengthKm?: number } = {}): FakeRoute {
  const built: FakeLeg[] = [];
  let start: LatLon = [52, 5];
  for (const edges of legs) {
    const leg = fakeLeg(edges, start, step);
    built.push(leg);
    start = leg.coords.at(-1)!;
  }
  const coords = built.flatMap((l, i) => (i === 0 ? l.coords : l.coords.slice(1)));
  let offset = 0;
  const edges = built.flatMap((l) => {
    const shifted = l.edges.map((e) => ({ ...e, begin_shape_index: e.begin_shape_index + offset, end_shape_index: e.end_shape_index + offset }));
    offset += l.coords.length - 1;
    return shifted;
  });
  return {
    shape: encodePolyline6(coords),
    coords,
    edges,
    legs: built,
    lengthKm: lengthKm ?? legs.flat().reduce((s, e) => s + e.km, 0),
  };
}

export function fakeRoute(edges: FakeEdge[], lengthKm?: number, step?: number): FakeRoute {
  return fakeLegs([edges], { ...(lengthKm === undefined ? {} : { lengthKm }), ...(step === undefined ? {} : { step }) });
}

export type Pick = (body: ValhallaBody, call: number) => FakeRoute | FakeRoute[] | Error;

export interface FakeValhalla extends ValhallaClient {
  calls: ValhallaBody[];
  walked: string[];
}

function osrmRoute(r: FakeRoute) {
  return {
    geometry: r.shape,
    distance: r.lengthKm * 1000,
    legs: r.legs.map((l) => ({
      steps: [{ geometry: l.shape }, { geometry: encodePolyline6([l.coords.at(-1)!, l.coords.at(-1)!]) }],
    })),
  };
}

function nativeTrip(r: FakeRoute) {
  return { legs: r.legs.map((l) => ({ shape: l.shape, maneuvers: [] })), summary: { length: r.lengthKm } };
}

export function fakeValhalla(pick: Pick): FakeValhalla {
  const byShape = new Map<string, TraceEdge[]>();
  const calls: ValhallaBody[] = [];
  const walked: string[] = [];
  return {
    calls,
    walked,
    async route(body) {
      const result = pick(body, calls.length);
      calls.push(body);
      if (result instanceof Error) throw result;
      const routes = Array.isArray(result) ? result : [result];
      for (const r of routes) for (const l of r.legs) byShape.set(l.shape, l.edges);
      const [first, ...rest] = routes;
      const response: ValhallaResponse =
        body.format === "osrm"
          ? { code: "Ok", waypoints: [], routes: routes.map(osrmRoute) }
          : { trip: nativeTrip(first!), ...(rest.length ? { alternates: rest.map((r) => ({ trip: nativeTrip(r) })) } : {}) };
      return response;
    },
    async edgeWalk(shape) {
      walked.push(shape);
      const edges = byShape.get(shape);
      if (!edges) throw new Error("edge walk on an unknown shape");
      return edges;
    },
    async status() {
      return true;
    },
  };
}
