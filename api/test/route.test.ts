import { describe, expect, it } from "vitest";
import type { FusedStatus } from "../src/fused.js";
import { planRoute, type RouteRequest } from "../src/route.js";
import { ValhallaError } from "../src/valhalla.js";
import { fakeRoute, fakeValhalla, type Pick } from "./fake-valhalla.js";

const fused = new Map<number, FusedStatus>([[20, "unknown"]]);

const crossing = fakeRoute([
  { way_id: 1, km: 1 },
  { way_id: 20, use: "cycleway", km: 0.5 },
  { way_id: 2, km: 1 },
]);
const detour = fakeRoute([
  { way_id: 1, km: 1 },
  { way_id: 3, km: 0.8 },
  { way_id: 4, km: 0.9 },
  { way_id: 2, km: 1 },
]);

const request = (overrides: Partial<RouteRequest> = {}): RouteRequest => ({
  origin: { lat: 52.29, lon: 5.44 },
  destination: { lat: 52.04, lon: 5.4 },
  verifiedOnly: false,
  format: "valhalla",
  language: "nl-NL",
  ...overrides,
});

const plan = (pick: Pick, req: RouteRequest) => {
  const valhalla = fakeValhalla(pick);
  return { valhalla, result: planRoute({ valhalla, fused, maxVerifiedRequests: 5 }, req) };
};

describe("route request", () => {
  it("always asks for motor_scooter with the time-dependent search", async () => {
    const { valhalla, result } = plan(() => crossing, request());
    await result;
    expect(valhalla.calls[0]).toEqual({
      locations: [
        { lat: 52.29, lon: 5.44 },
        { lat: 52.04, lon: 5.4 },
      ],
      costing: "motor_scooter",
      date_time: { type: 0 },
      directions_options: { units: "kilometers", language: "nl-NL" },
    });
  });

  it("asks for the extended OSRM format with banner and voice instructions", async () => {
    const { valhalla, result } = plan(() => crossing, request({ format: "osrm" }));
    const { response, naviscoot } = await result;
    expect(valhalla.calls[0]).toMatchObject({ format: "osrm", banner_instructions: true, voice_instructions: true });
    expect(response.routes).toBeDefined();
    expect(naviscoot.totals_m.unverified).toBe(500);
  });

  it("classifies the default route without a verified-only loop", async () => {
    const { valhalla, result } = plan(() => crossing, request());
    const { naviscoot } = await result;
    expect(valhalla.calls).toHaveLength(1);
    expect(naviscoot.stretches.map((s) => s.class)).toEqual(["carriageway", "unverified", "carriageway"]);
    expect(naviscoot.verified_only).toBeUndefined();
    expect(naviscoot.stretches[1]?.unavoidable).toBeUndefined();
  });
});

describe("verified-only", () => {
  it("excludes unverified edge midpoints and re-requests until none remain", async () => {
    const { valhalla, result } = plan((body) => (body.exclude_locations ? detour : crossing), request({ verifiedOnly: true }));
    const { naviscoot } = await result;
    expect(valhalla.calls).toHaveLength(2);
    const [a, b] = [crossing.coords[1]!, crossing.coords[2]!];
    expect(valhalla.calls[1]?.exclude_locations).toEqual([{ lat: (a[0] + b[0]) / 2, lon: (a[1] + b[1]) / 2 }]);
    expect(valhalla.calls[1]?.date_time).toEqual({ type: 0 });
    expect(naviscoot.stretches.some((s) => s.class === "unverified")).toBe(false);
    expect(naviscoot.verified_only).toEqual({ requests: 2, excluded_points: 1, converged: true });
  });

  it("keeps the exclude points of earlier requests", async () => {
    const second = fakeRoute([
      { way_id: 1, km: 1 },
      { way_id: 20, use: "cycleway", km: 0.2 },
      { way_id: 5, km: 0.2 },
      { way_id: 2, km: 1 },
    ]);
    const routes = [crossing, second, detour];
    const { valhalla, result } = plan((_, call) => routes[call]!, request({ verifiedOnly: true }));
    const { naviscoot } = await result;
    expect((valhalla.calls[2]?.exclude_locations as unknown[]).length).toBe(2);
    expect(naviscoot.verified_only).toEqual({ requests: 3, excluded_points: 2, converged: true });
  });

  it("leaves an unverified first or last edge alone and labels it as an endpoint", async () => {
    const startsOnUnverified = fakeRoute([
      { way_id: 20, use: "cycleway", km: 0.3 },
      { way_id: 1, km: 1 },
    ]);
    const { valhalla, result } = plan(() => startsOnUnverified, request({ verifiedOnly: true }));
    const { naviscoot } = await result;
    expect(valhalla.calls).toHaveLength(1);
    expect(naviscoot.stretches[0]).toMatchObject({ class: "unverified", unavoidable: "endpoint" });
    expect(naviscoot.verified_only?.converged).toBe(true);
  });

  it("returns the last route with unavoidable stretches when a re-request fails", async () => {
    const pick: Pick = (body) => (body.exclude_locations ? new ValhallaError("No path could be found", 400, 442) : crossing);
    const { result } = plan(pick, request({ verifiedOnly: true }));
    const { naviscoot } = await result;
    expect(naviscoot.stretches[1]).toMatchObject({ class: "unverified", unavoidable: "no_alternative" });
    expect(naviscoot.verified_only).toMatchObject({ requests: 2, excluded_points: 0, converged: false });
    expect(naviscoot.verified_only?.stopped_because).toContain("No path");
  });

  it("stops at the request cap", async () => {
    const { valhalla, result } = plan(() => crossing, request({ verifiedOnly: true }));
    const { naviscoot } = await result;
    expect(valhalla.calls).toHaveLength(5);
    expect(naviscoot.verified_only).toMatchObject({ requests: 5, converged: false });
    expect(naviscoot.stretches[1]?.unavoidable).toBe("no_alternative");
  });

  it("fails when no route exists at all", async () => {
    const { result } = plan(() => new ValhallaError("No path could be found", 400, 442), request({ verifiedOnly: true }));
    await expect(result).rejects.toBeInstanceOf(ValhallaError);
  });
});
