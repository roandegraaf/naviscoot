import { readFile } from "node:fs/promises";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { type FusedStatus, loadFused } from "../src/fused.js";
import { ReportStore } from "../src/reports.js";
import { FASTEST_CANDIDATES, fastestSlackS } from "../src/route.js";
import { decodePolyline6 } from "../src/polyline.js";
import { httpValhalla } from "../src/valhalla.js";

const config = loadConfig({ ...process.env, API_KEY: "integration-key" });
const valhalla = httpValhalla(config.valhallaUrl);
const available = await valhalla.status();
if (!available && process.env.REQUIRE_VALHALLA === "1") {
  throw new Error(`REQUIRE_VALHALLA=1 but no Valhalla answers at ${config.valhallaUrl}`);
}

interface Case {
  id: string;
  points: [number, number][];
  max_requests?: number;
}
const casesFile = process.env.REGRESSION_CASES ?? new URL("../../routing/regression_cases.json", import.meta.url);
const cases: Case[] = JSON.parse(await readFile(casesFile, "utf8")).cases;
const caseById = (id: string) => {
  const c = cases.find((x) => x.id === id);
  if (!c) throw new Error(`regression case ${id} missing`);
  return c;
};
const body = (c: Case, extra: Record<string, unknown> = {}) => ({
  origin: { lat: c.points[0]![0], lon: c.points[0]![1] },
  destination: { lat: c.points[1]![0], lon: c.points[1]![1] },
  ...extra,
});

interface Stretch {
  class: string;
  start_shape_index: number;
  end_shape_index: number;
  length_m: number;
  way_ids: number[];
  first_edge: number;
}
interface Naviscoot {
  length_m: number;
  edge_length_m: number;
  totals_m: Record<string, number>;
  stretches: Stretch[];
  speed_limits: { start_shape_index: number; end_shape_index: number; kmh: number }[];
  warnings: string[];
  verified_only?: { requests: number; converged: boolean };
  legs?: { start_shape_index: number; end_shape_index: number; first_edge: number; last_edge: number }[];
  avoid_unpaved?: { converged: boolean; remaining_m: number };
  route_id: string;
  alternates?: Naviscoot[];
}

interface WalkedEdge {
  length: number;
  road_class?: string;
  use?: string;
  unpaved?: boolean;
}

async function walkEdges(shape: string): Promise<WalkedEdge[]> {
  const res = await fetch(`${config.valhallaUrl}/trace_attributes`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      encoded_polyline: shape,
      shape_match: "edge_walk",
      costing: "motor_scooter",
      filters: { attributes: ["edge.length", "edge.road_class", "edge.use", "edge.unpaved"], action: "include" },
    }),
  });
  return ((await res.json()) as { edges: WalkedEdge[] }).edges;
}

const mainRoadKm = (edges: WalkedEdge[]) =>
  edges.filter((e) => (e.road_class === "primary" || e.road_class === "trunk") && e.use !== "ferry").reduce((s, e) => s + e.length, 0);

function interiorUnpavedKm(edges: WalkedEdge[]): number {
  let first = 0;
  let last = edges.length - 1;
  while (first <= last && edges[first]?.unpaved) first++;
  while (last >= first && edges[last]?.unpaved) last--;
  return edges.slice(first, last + 1).filter((e) => e.unpaved).reduce((s, e) => s + e.length, 0);
}

const distanceM = (a: [number, number], b: { lat: number; lon: number }) =>
  Math.hypot((a[0] - b.lat) * 111_320, (a[1] - b.lon) * 111_320 * Math.cos((b.lat * Math.PI) / 180));

function expectContiguous(n: Naviscoot, geometryPoints: number) {
  expect(n.stretches[0]?.start_shape_index).toBe(0);
  expect(n.stretches.at(-1)?.end_shape_index).toBe(geometryPoints - 1);
  n.stretches.slice(1).forEach((s, i) => expect(s.start_shape_index).toBe(n.stretches[i]!.end_shape_index));
  expect(n.speed_limits.at(-1)?.end_shape_index).toBe(geometryPoints - 1);
}

function expectEveryUnverifiedUnavoidable(n: Naviscoot) {
  for (const s of n.stretches.filter((x) => x.class === "unverified")) {
    expect((s as Stretch & { unavoidable?: string }).unavoidable).toBeDefined();
  }
}

const EDGE_TOLERANCE = 0.001;

function expectTotalsAddUp(n: Naviscoot, routeLengthM: number, edgeTolerance = EDGE_TOLERANCE) {
  expect(n.length_m).toBe(Math.round(routeLengthM));
  expect(Object.values(n.totals_m).reduce((a, b) => a + b, 0)).toBe(n.length_m);
  expect(Math.abs(n.edge_length_m - n.length_m) / n.length_m).toBeLessThan(edgeTolerance);
  expect(n.warnings).toEqual([]);
  expect(n.totals_m.forbidden).toBe(0);
}

describe.skipIf(!available)("against the local Valhalla", () => {
  let app: FastifyInstance;
  let fused: Map<number, FusedStatus>;
  const headers = { "x-api-key": "integration-key" };

  beforeAll(async () => {
    fused = await loadFused(config.fusedCsvPath);
    const dir = await mkdtemp(join(tmpdir(), "naviscoot-it-"));
    app = buildApp({
      apiKey: "integration-key",
      valhalla,
      fused,
      reports: await ReportStore.open(join(dir, "reports.jsonl")),
      maxVerifiedRequests: config.maxVerifiedRequests,
      fastestCandidates: FASTEST_CANDIDATES,
    });
  });
  afterAll(() => app.close());

  const route = async (payload: object) => {
    const res = await app.inject({ method: "POST", url: "/route", payload, headers });
    expect(res.statusCode, res.body).toBe(200);
    return res.json();
  };

  it("refuses a route request without the key", async () => {
    const res = await app.inject({ method: "POST", url: "/route", payload: body(caseById("verified-only-north-south")) });
    expect(res.statusCode).toBe(401);
  });

  it("classifies the unknown cycle path on verified-only-north-south as unverified and the totals add up", async () => {
    const res = await route(body(caseById("verified-only-north-south")));
    const n: Naviscoot = res.naviscoot;
    expectTotalsAddUp(n, res.trip.summary.length * 1000);
    const unverified = n.stretches.filter((s) => s.class === "unverified");
    expect(unverified.length).toBeGreaterThan(0);
    for (const s of unverified) for (const w of s.way_ids) expect(fused.get(w)).toBe("unknown");
    expect(n.totals_m.unverified).toBeGreaterThan(400);
    expect(n.totals_m.unverified).toBeLessThan(600);
    expect(n.totals_m.carriageway).toBeGreaterThan(0);
    expect(n.totals_m.moped_path).toBeGreaterThan(0);
  });

  it("covers verified-only-north-south with speed limit runs that give paths the graph's 30 or 40", async () => {
    const res = await route(body(caseById("verified-only-north-south")));
    const n: Naviscoot = res.naviscoot;
    const runs = n.speed_limits;
    expect(runs[0]?.start_shape_index).toBe(0);
    expect(runs.at(-1)?.end_shape_index).toBe(n.stretches.at(-1)?.end_shape_index);
    runs.slice(1).forEach((r, i) => expect(r.start_shape_index).toBe(runs[i]!.end_shape_index));
    const limitAt = (index: number) => runs.find((r) => r.start_shape_index <= index && index < r.end_shape_index)?.kmh;
    for (const s of n.stretches) {
      const kmh = limitAt(s.start_shape_index);
      if (s.class === "carriageway") expect(kmh).toBe(45);
      else expect([30, 40]).toContain(kmh);
    }
    expect(new Set(runs.map((r) => r.kmh))).toEqual(new Set([30, 40, 45]));
  });

  it("returns no unverified stretch at all when verified-only is requested", async () => {
    const c = caseById("verified-only-north-south");
    const res = await route(body(c, { verified_only: true }));
    const n: Naviscoot = res.naviscoot;
    expectTotalsAddUp(n, res.trip.summary.length * 1000);
    expect(n.stretches.filter((s) => s.class === "unverified")).toEqual([]);
    expect(n.totals_m.unverified).toBe(0);
    expect(n.verified_only?.converged).toBe(true);
    expect(n.verified_only?.requests).toBeLessThanOrEqual(c.max_requests ?? 5);
  });

  it("classifies the OSRM format response the same way", async () => {
    const res = await route(body(caseById("verified-only-north-south"), { format: "osrm" }));
    expect(res.code).toBe("Ok");
    expect(res.routes[0].legs[0].steps[0].voiceInstructions).toBeDefined();
    const n: Naviscoot = res.naviscoot;
    expectTotalsAddUp(n, res.routes[0].distance);
    expect(n.totals_m.unverified).toBeGreaterThan(400);
  });

  it("follows the N237 moped paths from Utrecht Domplein to Amersfoort", async () => {
    const res = await route(body(caseById("utrecht-domplein-to-amersfoort")));
    const n: Naviscoot = res.naviscoot;
    expectTotalsAddUp(n, res.trip.summary.length * 1000);
    expect(n.length_m).toBeLessThan(25_000);
    expect(n.totals_m.moped_path).toBeGreaterThan(5_000);
  });

  it("answers 422 when Valhalla has no route", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/route",
      payload: { origin: { lat: 40, lon: -30 }, destination: { lat: 52.1561, lon: 5.3878 } },
      headers,
    });
    expect(res.statusCode, res.body).toBe(422);
    expect(res.json().error).toBe("no_route");
  });

  it("classifies a route longer than 200 km (Groningen to Maastricht)", async () => {
    const res = await route({ origin: { lat: 53.2105, lon: 6.5641 }, destination: { lat: 50.8497, lon: 5.7053 } });
    const n: Naviscoot = res.naviscoot;
    expect(n.length_m).toBeGreaterThan(200_000);
    expectTotalsAddUp(n, res.trip.summary.length * 1000);
  }, 15_000);

  describe("waypoints", () => {
    const domplein = { lat: 52.0907, lon: 5.1214 };
    const amersfoort = { lat: 52.1561, lon: 5.3878 };
    const stops = [
      { lat: 52.11, lon: 5.2 },
      { lat: 52.13, lon: 5.3 },
    ];

    it("routes through two stops in order with one index space over the OSRM geometry", async () => {
      const res = await route({ origin: domplein, destination: amersfoort, waypoints: stops, format: "osrm" });
      const coords = decodePolyline6(res.routes[0].geometry);
      const n: Naviscoot = res.naviscoot;
      expect(res.routes[0].legs).toHaveLength(3);
      expect(res.waypoints).toHaveLength(4);
      expectTotalsAddUp(n, res.routes[0].distance);
      expectContiguous(n, coords.length);
      expect(n.legs).toHaveLength(3);
      expect(n.legs![0]!.start_shape_index).toBe(0);
      expect(n.legs!.at(-1)!.end_shape_index).toBe(coords.length - 1);
      n.legs!.slice(1).forEach((leg, i) => {
        expect(leg.start_shape_index).toBe(n.legs![i]!.end_shape_index);
        expect(leg.first_edge).toBe(n.legs![i]!.last_edge + 1);
        const [lon, lat] = res.waypoints[i + 1].location;
        expect(distanceM(coords[leg.start_shape_index]!, { lat, lon })).toBeLessThan(0.5);
      });
    });

    it("gives the native format the same legs and classification", async () => {
      const payload = { origin: domplein, destination: amersfoort, waypoints: stops };
      const native = await route(payload);
      const osrm = await route({ ...payload, format: "osrm" });
      expect(native.trip.legs).toHaveLength(3);
      expect(native.naviscoot.legs).toEqual(osrm.naviscoot.legs);
      expect(native.naviscoot.totals_m).toEqual(osrm.naviscoot.totals_m);
      const points = native.trip.legs.reduce((sum: number, l: { shape: string }) => sum + decodePolyline6(l.shape).length - 1, 1);
      expect(native.naviscoot.legs.at(-1).end_shape_index).toBe(points - 1);
    });

    it("classifies a trip that turns around at a stop, where one edge walk over the whole geometry fails", async () => {
      const origin = { lat: 52.1542, lon: 5.3842 };
      const res = await route({ origin, destination: origin, waypoints: [{ lat: 52.156, lon: 5.387 }], format: "osrm" });
      const n: Naviscoot = res.naviscoot;
      expectTotalsAddUp(n, res.routes[0].distance, 0.005);
      expect(n.legs).toHaveLength(2);
      expect(await walkEdges(res.routes[0].geometry).catch(() => undefined)).toBeUndefined();
    });

    it("classifies a trip with the same stop twice in both formats", async () => {
      for (const format of ["osrm", "valhalla"]) {
        const res = await route({ origin: domplein, destination: amersfoort, waypoints: [stops[0], stops[0]], format });
        const n: Naviscoot = res.naviscoot;
        expect(n.legs).toHaveLength(3);
        expect(Object.values(n.totals_m).reduce((a, b) => a + b, 0)).toBe(n.length_m);
        expect(n.totals_m.forbidden).toBe(0);
        expect(n.warnings).toEqual([]);
      }
    });

    it("keeps verified-only working through a stop", async () => {
      const c = caseById("verified-only-north-south");
      const res = await route(body(c, { waypoints: [{ lat: 52.2, lon: 5.42 }], verified_only: true, format: "osrm" }));
      const n: Naviscoot = res.naviscoot;
      expectTotalsAddUp(n, res.routes[0].distance);
      expect(n.totals_m.unverified).toBe(0);
      expect(n.verified_only?.converged).toBe(true);
    });
  });

  describe("alternatives", () => {
    it("keeps the time-dependent N237 route first and adds classified alternatives", async () => {
      const res = await route(body(caseById("utrecht-domplein-to-amersfoort"), { alternatives: 2, format: "osrm" }));
      const n: Naviscoot = res.naviscoot;
      expect(res.routes[0].distance).toBeGreaterThan(22_000);
      expect(res.routes[0].distance).toBeLessThan(22_400);
      expect(res.routes.length).toBeGreaterThanOrEqual(2);
      expect(res.routes.length).toBeLessThanOrEqual(3);
      const metas = [n, ...(n.alternates ?? [])];
      expect(metas).toHaveLength(res.routes.length);
      expect(new Set(metas.map((m) => m.route_id)).size).toBe(metas.length);
      metas.forEach((m, i) => {
        expectTotalsAddUp(m, res.routes[i].distance);
        expectContiguous(m, decodePolyline6(res.routes[i].geometry).length);
      });
    });

    it("applies verified-only to each alternative on its own", async () => {
      const res = await route(body(caseById("verified-only-north-south"), { alternatives: 2, verified_only: true, format: "osrm" }));
      const metas: Naviscoot[] = [res.naviscoot, ...(res.naviscoot.alternates ?? [])];
      expect(metas.length).toBeGreaterThanOrEqual(2);
      metas.forEach((m, i) => {
        expectTotalsAddUp(m, res.routes[i].distance);
        expectEveryUnverifiedUnavoidable(m);
        expect(m.verified_only).toBeDefined();
      });
      expect(res.naviscoot.totals_m.unverified).toBe(0);
    });
  });

  describe("departure and arrival time", () => {
    it("plans with a departure time and with an arrival time, also through a stop", async () => {
      const c = caseById("utrecht-domplein-to-amersfoort");
      const depart = await route(body(c, { depart_at: "2026-11-16T08:00:00+01:00" }));
      expect(depart.trip.locations[0].date_time).toBe("2026-11-16T08:00");
      const arrive = await route(body(c, { arrive_by: "2026-11-16T09:00:00+01:00", waypoints: [{ lat: 52.11, lon: 5.2 }] }));
      expect(arrive.trip.legs).toHaveLength(2);
      expect(arrive.trip.locations.at(-1).date_time).toBe("2026-11-16T09:00");
      expectTotalsAddUp(arrive.naviscoot, arrive.trip.summary.length * 1000);
    });
  });

  describe("avoid", () => {
    it("avoids the IJ ferry", async () => {
      const payload = { origin: { lat: 52.3795, lon: 4.8995 }, destination: { lat: 52.3848, lon: 4.905 } };
      expect((await route(payload)).trip.summary.has_ferry).toBe(true);
      const avoided = await route({ ...payload, avoid: { ferries: true } });
      expect(avoided.trip.summary.has_ferry).toBe(false);
      expectTotalsAddUp(avoided.naviscoot, avoided.trip.summary.length * 1000);
    });

    it("avoids an unpaved road in the middle of the route", async () => {
      const payload = { origin: { lat: 52.10483, lon: 5.60555 }, destination: { lat: 52.07886, lon: 5.66514 } };
      const plain = await route(payload);
      expect(interiorUnpavedKm(await walkEdges(plain.trip.legs[0].shape))).toBeGreaterThan(0.3);
      const avoided = await route({ ...payload, avoid: { unpaved: true } });
      expect(avoided.naviscoot.avoid_unpaved).toEqual({ converged: true, remaining_m: 0 });
      expect(interiorUnpavedKm(await walkEdges(avoided.trip.legs[0].shape))).toBe(0);
      expectTotalsAddUp(avoided.naviscoot, avoided.trip.summary.length * 1000);
    });

    it("keeps the fastest route within the slack of the quickest costing through Arnhem", async () => {
      const payload = { origin: { lat: 51.97709, lon: 5.89902 }, destination: { lat: 51.95638, lon: 5.90813 } };
      const planned = await route(payload);
      const times = await Promise.all(
        [{}, ...FASTEST_CANDIDATES].map(async (costing) => {
          const res = await fetch(`${config.valhallaUrl}/route`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              locations: [payload.origin, payload.destination],
              costing: "motor_scooter",
              costing_options: { motor_scooter: costing },
              date_time: { type: 0 },
              directions_type: "none",
            }),
          });
          return ((await res.json()) as { trip: { summary: { time: number } } }).trip.summary.time;
        }),
      );
      expect(planned.naviscoot.profile).toBe("fastest");
      const quickest = Math.min(...times);
      expect(planned.trip.summary.time).toBeLessThanOrEqual(quickest + fastestSlackS(quickest));
    });

    it("avoids the primary road through Arnhem", async () => {
      const payload = { origin: { lat: 51.97709, lon: 5.89902 }, destination: { lat: 51.95638, lon: 5.90813 } };
      expect(mainRoadKm(await walkEdges((await route(payload)).trip.legs[0].shape))).toBeGreaterThan(1);
      const avoided = await route({ ...payload, avoid: { main_roads: true } });
      expect(avoided.naviscoot.profile).toBe("quiet");
      expect(mainRoadKm(await walkEdges(avoided.trip.legs[0].shape))).toBeLessThan(0.05);
    });
  });
});
