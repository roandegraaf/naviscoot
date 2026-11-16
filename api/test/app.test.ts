import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FastifyInstance } from "fastify";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { FusedStatus } from "../src/fused.js";
import { ReportStore } from "../src/reports.js";
import { ValhallaError } from "../src/valhalla.js";
import { fakeLegs, fakeRoute, fakeValhalla, type Pick } from "./fake-valhalla.js";

const KEY = "test-key-0123456789";
const fused = new Map<number, FusedStatus>([[20, "unknown"]]);
const crossing = fakeRoute([
  { way_id: 1, km: 1 },
  { way_id: 20, use: "cycleway", km: 0.5 },
  { way_id: 2, km: 1 },
]);
const routeBody = { origin: { lat: 52.29, lon: 5.44 }, destination: { lat: 52.04, lon: 5.4 } };

let dir: string;
let apps: FastifyInstance[] = [];

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "naviscoot-api-"));
});

afterEach(async () => {
  await Promise.all(apps.map((a) => a.close()));
  apps = [];
});

async function makeApp(pick: Pick = () => crossing, reportsPath = join(dir, "reports.jsonl")) {
  const app = buildApp({
    apiKey: KEY,
    valhalla: fakeValhalla(pick),
    fused,
    reports: await ReportStore.open(reportsPath),
    maxVerifiedRequests: 5,
  });
  apps.push(app);
  return app;
}

describe("auth", () => {
  it.each([
    ["POST", "/route", routeBody],
    ["GET", "/reports", undefined],
    ["POST", "/reports", { lat: 52, lon: 5 }],
  ] as const)("refuses %s %s without a key", async (method, url, payload) => {
    const app = await makeApp();
    const res = await app.inject({ method, url, payload });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: "unauthorized" });
  });

  it("refuses a wrong key", async () => {
    const app = await makeApp();
    const res = await app.inject({ method: "POST", url: "/route", payload: routeBody, headers: { "x-api-key": "nope" } });
    expect(res.statusCode).toBe(401);
  });

  it("checks the key before validating the body", async () => {
    const app = await makeApp();
    const res = await app.inject({ method: "POST", url: "/route", payload: { origin: "x" } });
    expect(res.statusCode).toBe(401);
  });

  it("refuses unknown paths without a key", async () => {
    const app = await makeApp();
    expect((await app.inject({ method: "GET", url: "/nope" })).statusCode).toBe(401);
  });

  it("leaves the health check open", async () => {
    const app = await makeApp();
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: "ok", valhalla: true });
  });
});

describe("POST /route", () => {
  it("returns the Valhalla response with the classification beside it", async () => {
    const app = await makeApp();
    const res = await app.inject({ method: "POST", url: "/route", payload: routeBody, headers: { "x-api-key": KEY } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.trip.legs[0].shape).toBe(crossing.shape);
    expect(body.naviscoot.totals_m).toEqual({ carriageway: 2000, moped_path: 0, unverified: 500, forbidden: 0 });
    expect(body.naviscoot.length_m).toBe(2500);
    expect(body.naviscoot.route_id).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("returns the OSRM object at the top level for format osrm", async () => {
    const app = await makeApp();
    const res = await app.inject({
      method: "POST",
      url: "/route",
      payload: { ...routeBody, format: "osrm" },
      headers: { "x-api-key": KEY },
    });
    const body = res.json();
    expect(body.code).toBe("Ok");
    expect(body.routes[0].geometry).toBe(crossing.shape);
    expect(body.naviscoot.format).toBe("osrm");
  });

  it("rejects an invalid body with 400", async () => {
    const app = await makeApp();
    const res = await app.inject({
      method: "POST",
      url: "/route",
      payload: { origin: { lat: 95, lon: 5 }, destination: routeBody.destination },
      headers: { "x-api-key": KEY },
    });
    expect(res.statusCode).toBe(400);
  });

  it("answers 422 when Valhalla finds no route and 502 when it is down", async () => {
    const noPath = await makeApp(() => new ValhallaError("valhalla route 400: No path could be found", 400, 442));
    const res = await noPath.inject({ method: "POST", url: "/route", payload: routeBody, headers: { "x-api-key": KEY } });
    expect(res.statusCode).toBe(422);
    expect(res.json().error).toBe("no_route");

    const down = await makeApp(() => new ValhallaError("valhalla route unreachable", 0));
    const res2 = await down.inject({ method: "POST", url: "/route", payload: routeBody, headers: { "x-api-key": KEY } });
    expect(res2.statusCode).toBe(502);
    expect(res2.json().error).toBe("valhalla_unavailable");
  });

  it("does not claim there is no route when only the edge walk fails", async () => {
    const valhalla = fakeValhalla(() => crossing);
    valhalla.edgeWalk = async () => {
      throw new ValhallaError("valhalla trace_attributes 400: Exceeded max distance", 400, 154);
    };
    const app = buildApp({ apiKey: KEY, valhalla, fused, reports: await ReportStore.open(join(dir, "r.jsonl")), maxVerifiedRequests: 5 });
    apps.push(app);
    const res = await app.inject({ method: "POST", url: "/route", payload: routeBody, headers: { "x-api-key": KEY } });
    expect(res.statusCode).toBe(502);
    expect(res.json().error).toBe("classification_failed");
  });
});

describe("POST /route options", () => {
  const headers = { "x-api-key": KEY };
  const stop = { lat: 52.2, lon: 5.42 };
  const post = async (payload: object) => (await makeApp()).inject({ method: "POST", url: "/route", payload, headers });

  it("accepts up to 8 waypoints and rejects 9 with too_many_waypoints", async () => {
    const legs = (n: number) => fakeLegs(Array.from({ length: n }, (_, i) => [{ way_id: 100 + i, km: 1 }]));
    const eight = await (await makeApp(() => legs(9))).inject({
      method: "POST",
      url: "/route",
      payload: { ...routeBody, waypoints: Array(8).fill(stop) },
      headers,
    });
    expect(eight.statusCode, eight.body).toBe(200);
    expect(eight.json().naviscoot.legs).toHaveLength(9);

    const nine = await post({ ...routeBody, waypoints: Array(9).fill(stop) });
    expect(nine.statusCode).toBe(400);
    expect(nine.json()).toMatchObject({ error: "too_many_waypoints" });
  });

  it("rejects depart_at together with arrive_by", async () => {
    const res = await post({ ...routeBody, depart_at: "2026-11-16T08:00:00+01:00", arrive_by: "2026-11-16T09:00:00+01:00" });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: "conflicting_times" });
  });

  it("rejects alternatives on a trip with waypoints", async () => {
    const res = await post({ ...routeBody, waypoints: [stop], alternatives: 1 });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: "alternatives_need_two_points" });
  });

  it.each([
    ["more than 2 alternatives", { alternatives: 3 }],
    ["a negative alternatives count", { alternatives: -1 }],
    ["a time that is not ISO 8601", { depart_at: "tomorrow 8:00" }],
    ["an avoid option that is not a boolean", { avoid: { ferries: "yes" } }],
    ["a waypoint without lon", { waypoints: [{ lat: 52 }] }],
  ])("rejects %s as an invalid body", async (_, extra) => {
    expect((await post({ ...routeBody, ...extra })).statusCode).toBe(400);
  });

  it("accepts every new field together on a two-point trip", async () => {
    const res = await post({
      ...routeBody,
      alternatives: 2,
      arrive_by: "2026-11-16T09:00:00+01:00",
      avoid: { ferries: true, unpaved: true, main_roads: true },
      format: "osrm",
    });
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().naviscoot.alternates).toEqual([]);
    expect(res.json().naviscoot.avoid_unpaved).toEqual({ converged: true, remaining_m: 0 });
  });
});

describe("reports", () => {
  const headers = { "x-api-key": KEY };

  it("stores position, time, note and route id and lists them", async () => {
    const app = await makeApp();
    const posted = await app.inject({
      method: "POST",
      url: "/reports",
      headers,
      payload: { lat: 52.1561, lon: 5.3878, time: "2026-11-14T15:30:00+01:00", note: "G11 sign", route_id: "r1" },
    });
    expect(posted.statusCode).toBe(201);
    const report = posted.json();
    expect(report).toMatchObject({ lat: 52.1561, lon: 5.3878, time: "2026-11-14T14:30:00.000Z", note: "G11 sign", route_id: "r1" });
    expect(report.received_at).toBeTruthy();

    const listed = await app.inject({ method: "GET", url: "/reports", headers });
    expect(listed.json().reports).toEqual([report]);
  });

  it("defaults the time to the moment of receipt", async () => {
    const app = await makeApp();
    const report = (await app.inject({ method: "POST", url: "/reports", headers, payload: { lat: 52, lon: 5 } })).json();
    expect(report.time).toBe(report.received_at);
  });

  it("rejects reports without a position or with a bad time", async () => {
    const app = await makeApp();
    expect((await app.inject({ method: "POST", url: "/reports", headers, payload: { lat: 52 } })).statusCode).toBe(400);
    expect(
      (await app.inject({ method: "POST", url: "/reports", headers, payload: { lat: 52, lon: 5, time: "yesterday" } })).statusCode,
    ).toBe(400);
  });

  it("survives a restart", async () => {
    const path = join(dir, "reports.jsonl");
    const first = await makeApp(undefined, path);
    const report = (await first.inject({ method: "POST", url: "/reports", headers, payload: { lat: 52, lon: 5 } })).json();
    await first.close();

    const second = await makeApp(undefined, path);
    const listed = await second.inject({ method: "GET", url: "/reports", headers });
    expect(listed.json().reports).toEqual([report]);
  });

  it("drops a partial last line left by a crash and keeps appending cleanly", async () => {
    const path = join(dir, "reports.jsonl");
    const store = await ReportStore.open(path);
    const kept = await store.add({ lat: 52, lon: 5 });
    await writeFile(path, `${JSON.stringify(kept)}\n{"id":"half`, { flag: "w" });

    const reopened = await ReportStore.open(path);
    expect(reopened.list()).toEqual([kept]);
    const next = await reopened.add({ lat: 53, lon: 6 });
    expect((await ReportStore.open(path)).list()).toEqual([kept, next]);
    expect((await readFile(path, "utf8")).split("\n").filter(Boolean)).toHaveLength(2);
  });
});
