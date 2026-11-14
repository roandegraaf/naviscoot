import { type LatLon, encodePolyline6 } from "../src/polyline.js";
import type { TraceEdge, ValhallaBody, ValhallaClient, ValhallaResponse } from "../src/valhalla.js";

export interface FakeEdge {
  way_id: number;
  use?: string;
  km: number;
}

export interface FakeRoute {
  shape: string;
  coords: LatLon[];
  edges: TraceEdge[];
  lengthKm: number;
}

export function fakeRoute(edges: FakeEdge[], lengthKm?: number): FakeRoute {
  const coords: LatLon[] = [[52, 5]];
  const trace: TraceEdge[] = edges.map((e, i) => {
    coords.push([52 + (i + 1) * 0.001, 5 + (i + 1) * 0.001]);
    return { way_id: e.way_id, length: e.km, use: e.use ?? "road", begin_shape_index: i, end_shape_index: i + 1 };
  });
  return {
    shape: encodePolyline6(coords),
    coords,
    edges: trace,
    lengthKm: lengthKm ?? edges.reduce((s, e) => s + e.km, 0),
  };
}

export type Pick = (body: ValhallaBody, call: number) => FakeRoute | Error;

export interface FakeValhalla extends ValhallaClient {
  calls: ValhallaBody[];
}

export function fakeValhalla(pick: Pick): FakeValhalla {
  const byShape = new Map<string, TraceEdge[]>();
  const calls: ValhallaBody[] = [];
  return {
    calls,
    async route(body) {
      const result = pick(body, calls.length);
      calls.push(body);
      if (result instanceof Error) throw result;
      byShape.set(result.shape, result.edges);
      const response: ValhallaResponse =
        body.format === "osrm"
          ? { code: "Ok", waypoints: [], routes: [{ geometry: result.shape, distance: result.lengthKm * 1000 }] }
          : { trip: { legs: [{ shape: result.shape, maneuvers: [] }], summary: { length: result.lengthKm } } };
      return response;
    },
    async edgeWalk(shape) {
      const edges = byShape.get(shape);
      if (!edges) throw new Error("edge walk on an unknown shape");
      return edges;
    },
    async status() {
      return true;
    },
  };
}
