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
const cases: Case[] = JSON.parse(await readFile(new URL("../../routing/regression_cases.json", import.meta.url), "utf8")).cases;
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
  length_m: number;
  way_ids: number[];
  first_edge: number;
}
interface Naviscoot {
  length_m: number;
  edge_length_m: number;
  totals_m: Record<string, number>;
  stretches: Stretch[];
  warnings: string[];
  verified_only?: { requests: number; converged: boolean };
}

const EDGE_TOLERANCE = 0.001;

function expectTotalsAddUp(n: Naviscoot, routeLengthM: number) {
  expect(n.length_m).toBe(Math.round(routeLengthM));
  expect(Object.values(n.totals_m).reduce((a, b) => a + b, 0)).toBe(n.length_m);
  expect(Math.abs(n.edge_length_m - n.length_m) / n.length_m).toBeLessThan(EDGE_TOLERANCE);
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
  });
});
