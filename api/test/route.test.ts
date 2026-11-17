import { describe, expect, it } from "vitest";
import type { FusedStatus } from "../src/fused.js";
import { type Costing, fastestSlackS, planRoute, QUIET_TOP_SPEED_KMH, type RouteRequest, valhallaBody, valhallaLocalTime } from "../src/route.js";
import { type ValhallaBody, ValhallaError } from "../src/valhalla.js";
import { FAKE_TRACED_SECONDS_PER_KM, fakeLegs, fakeRoute, fakeValhalla, type Pick } from "./fake-valhalla.js";

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

const NOW = new Date("2026-11-14T21:30:00Z");

const plan = (pick: Pick, req: RouteRequest) => {
  const valhalla = fakeValhalla(pick);
  return { valhalla, result: planRoute({ valhalla, fused, maxVerifiedRequests: 5 }, req, NOW) };
};

const isAlternatesCall = (body: ValhallaBody) => body.alternates !== undefined;

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

describe("waypoints", () => {
  const stops = [
    { lat: 52.2, lon: 5.43 },
    { lat: 52.1, lon: 5.41 },
  ];
  const threeLegs = fakeLegs([
    [
      { way_id: 1, km: 1 },
      { way_id: 2, km: 1 },
    ],
    [
      { way_id: 2, km: 0.5 },
      { way_id: 20, use: "cycleway", km: 0.4 },
      { way_id: 3, km: 1 },
    ],
    [{ way_id: 4, use: "cycleway", km: 1, speed_limit: 40 }],
  ]);

  it("sends the stops in order as break locations between origin and destination", async () => {
    const { valhalla, result } = plan(() => threeLegs, request({ waypoints: stops }));
    await result;
    expect(valhalla.calls[0]?.locations).toEqual([
      { lat: 52.29, lon: 5.44 },
      { lat: 52.2, lon: 5.43, type: "break" },
      { lat: 52.1, lon: 5.41, type: "break" },
      { lat: 52.04, lon: 5.4 },
    ]);
  });

  it.each(["valhalla", "osrm"] as const)("edge-walks each leg and indexes the joined %s geometry", async (format) => {
    const { valhalla, result } = plan(() => threeLegs, request({ waypoints: stops, format }));
    const { naviscoot } = await result;
    expect(valhalla.walked).toEqual(threeLegs.legs.map((l) => l.shape));
    expect(naviscoot.legs).toEqual([
      { start_shape_index: 0, end_shape_index: 2, first_edge: 0, last_edge: 1 },
      { start_shape_index: 2, end_shape_index: 5, first_edge: 2, last_edge: 4 },
      { start_shape_index: 5, end_shape_index: 6, first_edge: 5, last_edge: 5 },
    ]);
    expect(naviscoot.stretches.map((s) => [s.class, s.start_shape_index, s.end_shape_index])).toEqual([
      ["carriageway", 0, 3],
      ["unverified", 3, 4],
      ["carriageway", 4, 5],
      ["moped_path", 5, 6],
    ]);
    expect(naviscoot.speed_limits).toEqual([
      { start_shape_index: 0, end_shape_index: 3, kmh: 45 },
      { start_shape_index: 3, end_shape_index: 4, kmh: 30 },
      { start_shape_index: 4, end_shape_index: 5, kmh: 45 },
      { start_shape_index: 5, end_shape_index: 6, kmh: 40 },
    ]);
    expect(naviscoot.length_m).toBe(4900);
    expect(naviscoot.stretches.reduce((sum, s) => sum + s.length_m, 0)).toBe(4900);
  });

  it("fails loudly when the OSRM steps do not cover the geometry", async () => {
    const valhalla = fakeValhalla(() => threeLegs);
    const route = valhalla.route.bind(valhalla);
    valhalla.route = async (body) => {
      const response = await route(body);
      const legs = (response.routes as { legs: { steps: unknown[] }[] }[])[0]!.legs;
      legs[1]!.steps = legs[1]!.steps.slice(-1);
      return response;
    };
    const result = planRoute({ valhalla, fused, maxVerifiedRequests: 5 }, request({ waypoints: stops, format: "osrm" }), NOW);
    await expect(result).rejects.toThrow(/leg steps cover/);
  });

  it("does not edge-walk a zero-length leg between two snaps of the same stop", async () => {
    const valhalla = fakeValhalla(() => threeLegs);
    const route = valhalla.route.bind(valhalla);
    valhalla.route = async (body) => {
      const response = await route(body);
      (response.routes as { legs: { distance?: number }[] }[])[0]!.legs[2]!.distance = 0;
      return response;
    };
    const { naviscoot } = await planRoute({ valhalla, fused, maxVerifiedRequests: 5 }, request({ waypoints: stops, format: "osrm" }), NOW);
    expect(valhalla.walked).toEqual(threeLegs.legs.slice(0, 2).map((l) => l.shape));
    expect(naviscoot.legs?.[2]).toEqual({ start_shape_index: 5, end_shape_index: 6, first_edge: 5, last_edge: 4 });
    expect(naviscoot.stretches.at(-1)?.class).toBe("carriageway");
  });

  it("treats the edges next to a stop as endpoints in verified-only", async () => {
    const stopOnUnverified = fakeLegs([
      [
        { way_id: 1, km: 1 },
        { way_id: 20, use: "cycleway", km: 0.2 },
      ],
      [
        { way_id: 20, use: "cycleway", km: 0.2 },
        { way_id: 2, km: 1 },
      ],
    ]);
    const { valhalla, result } = plan(() => stopOnUnverified, request({ waypoints: [stops[0]!], verifiedOnly: true }));
    const { naviscoot } = await result;
    expect(valhalla.calls).toHaveLength(1);
    expect(naviscoot.stretches[1]).toMatchObject({ class: "unverified", start_shape_index: 1, end_shape_index: 3, unavoidable: "endpoint" });
    expect(naviscoot.verified_only).toEqual({ requests: 1, excluded_points: 0, converged: true });
  });

  it("excludes an unverified edge in the middle of a leg", async () => {
    const detourLeg = fakeLegs([[{ way_id: 1, km: 1 }], [{ way_id: 2, km: 1 }, { way_id: 5, km: 0.5 }, { way_id: 3, km: 1 }]]);
    const { valhalla, result } = plan(
      (body) => (body.exclude_locations ? detourLeg : threeLegs),
      request({ waypoints: stops, verifiedOnly: true }),
    );
    const { naviscoot } = await result;
    const [a, b] = [threeLegs.coords[3]!, threeLegs.coords[4]!];
    expect(valhalla.calls[1]?.exclude_locations).toEqual([{ lat: (a[0] + b[0]) / 2, lon: (a[1] + b[1]) / 2 }]);
    expect(naviscoot.totals_m.unverified).toBe(0);
    expect(naviscoot.verified_only?.converged).toBe(true);
  });

  it("leaves the legs key out of a two-point route", async () => {
    const { result } = plan(() => crossing, request());
    expect((await result).naviscoot.legs).toBeUndefined();
  });
});

describe("alternatives", () => {
  const altA = fakeRoute(
    [
      { way_id: 1, km: 1 },
      { way_id: 30, km: 2 },
      { way_id: 2, km: 1 },
    ],
    undefined,
    0.002,
  );
  const altB = fakeRoute(
    [
      { way_id: 1, km: 0.2 },
      { way_id: 40, km: 2 },
      { way_id: 41, km: 2 },
      { way_id: 2, km: 0.2 },
    ],
    undefined,
    0.003,
  );
  const sameAsPrimary = fakeRoute(
    [
      { way_id: 1, km: 1 },
      { way_id: 20, use: "cycleway", km: 0.5 },
      { way_id: 2, km: 1 },
    ],
    undefined,
    0.0011,
  );

  it("keeps the primary from the time-dependent search and takes the others from an invariant-time request", async () => {
    const { valhalla, result } = plan(
      (body) => (isAlternatesCall(body) ? [sameAsPrimary, altA, altB] : crossing),
      request({ alternatives: 2, format: "osrm" }),
    );
    const { response, naviscoot } = await result;
    const primaryCall = valhalla.calls.find((c) => !isAlternatesCall(c));
    const alternatesCall = valhalla.calls.find(isAlternatesCall);
    expect(primaryCall?.date_time).toEqual({ type: 0 });
    expect(alternatesCall).toMatchObject({ alternates: 2, date_time: { type: 3, value: "2026-11-14T22:30" } });

    const routes = response.routes as { geometry: string }[];
    expect(routes.map((r) => r.geometry)).toEqual([crossing.shape, altA.shape, altB.shape]);
    expect(naviscoot.alternates?.map((a) => a.length_m)).toEqual([4000, 4400]);
    const ids = [naviscoot.route_id, ...(naviscoot.alternates ?? []).map((a) => a.route_id)];
    expect(new Set(ids).size).toBe(3);
    expect(naviscoot.alternates?.[0]?.totals_m).toEqual({ carriageway: 4000, moped_path: 0, unverified: 0, forbidden: 0 });
  });

  it("returns at most the number asked for, in the native format under alternates", async () => {
    const { response, naviscoot } = await plan(
      (body) => (isAlternatesCall(body) ? [altA, altB] : crossing),
      request({ alternatives: 1 }),
    ).result;
    expect((response.alternates as { trip: { legs: { shape: string }[] } }[]).map((a) => a.trip.legs[0]?.shape)).toEqual([altA.shape]);
    expect(naviscoot.alternates).toHaveLength(1);
  });

  it("answers with the primary alone when the alternatives request finds nothing", async () => {
    const { response, naviscoot } = await plan(
      (body) => (isAlternatesCall(body) ? new ValhallaError("No path could be found", 400, 442) : crossing),
      request({ alternatives: 2, format: "osrm" }),
    ).result;
    expect(response.routes).toHaveLength(1);
    expect(naviscoot.alternates).toEqual([]);
  });

  it("applies verified-only to every alternative", async () => {
    const unverifiedAlt = fakeRoute(
      [
        { way_id: 1, km: 1 },
        { way_id: 21, use: "cycleway", km: 0.5 },
        { way_id: 30, km: 2 },
      ],
      undefined,
      0.004,
    );
    const valhallaFused = new Map(fused).set(21, "unknown");
    const valhalla = fakeValhalla((body) => {
      if (!isAlternatesCall(body)) return body.exclude_locations ? altA : crossing;
      return body.exclude_locations ? [altA, altB] : [unverifiedAlt, altB];
    });
    const { naviscoot } = await planRoute(
      { valhalla, fused: valhallaFused, maxVerifiedRequests: 5 },
      request({ alternatives: 2, verifiedOnly: true }),
      NOW,
    );
    expect(naviscoot.totals_m.unverified).toBe(0);
    for (const alt of naviscoot.alternates ?? []) {
      expect(alt.totals_m.unverified).toBe(0);
      expect(alt.verified_only).toMatchObject({ requests: 2, converged: true });
    }
    expect(naviscoot.alternates?.map((a) => a.length_m)).toEqual([4400]);
  });
});

describe("departure and arrival time", () => {
  it.each([
    ["2026-11-16T08:00:00+01:00", "2026-11-16T08:00"],
    ["2026-11-16T07:00:00Z", "2026-11-16T08:00"],
    ["2026-07-01T06:00:00Z", "2026-07-01T08:00"],
    ["2026-03-29T00:59:00Z", "2026-03-29T01:59"],
    ["2026-03-29T01:00:00Z", "2026-03-29T03:00"],
    ["2026-10-25T00:30:00Z", "2026-10-25T02:30"],
    ["2026-10-25T01:30:00Z", "2026-10-25T02:30"],
    ["2026-12-31T23:30:00Z", "2027-01-01T00:30"],
  ])("converts %s to Amsterdam wall-clock time %s", (iso, local) => {
    expect(valhallaLocalTime(new Date(iso))).toBe(local);
  });

  it("asks for a specified departure or arrival", async () => {
    const at = new Date("2026-11-16T07:00:00Z");
    const depart = plan(() => crossing, request({ time: { kind: "depart_at", at } }));
    await depart.result;
    expect(depart.valhalla.calls[0]?.date_time).toEqual({ type: 1, value: "2026-11-16T08:00" });

    const arrive = plan(() => crossing, request({ time: { kind: "arrive_by", at } }));
    await arrive.result;
    expect(arrive.valhalla.calls[0]?.date_time).toEqual({ type: 2, value: "2026-11-16T08:00" });
  });

  it("uses the requested time for the alternatives request too", async () => {
    const at = new Date("2026-11-16T07:00:00Z");
    const { valhalla, result } = plan(() => crossing, request({ alternatives: 1, time: { kind: "arrive_by", at } }));
    await result;
    expect(valhalla.calls.find(isAlternatesCall)?.date_time).toEqual({ type: 3, value: "2026-11-16T08:00" });
  });
});

describe("avoid", () => {
  it("adds no costing options when nothing is avoided", () => {
    expect(valhallaBody(request({ avoid: { ferries: false, unpaved: false, main_roads: false } }), [])).not.toHaveProperty("costing_options");
  });

  it("maps ferries onto use_ferry and main roads onto the quiet profile", () => {
    expect(valhallaBody(request({ avoid: { ferries: true } }), []).costing_options).toEqual({ motor_scooter: { use_ferry: 0 } });
    expect(valhallaBody(request({ avoid: { main_roads: true } }), []).costing_options).toEqual({
      motor_scooter: { use_primary: 0, top_speed: QUIET_TOP_SPEED_KMH },
    });
    expect(valhallaBody(request({ avoid: { ferries: true, main_roads: true, unpaved: true } }), []).costing_options).toEqual({
      motor_scooter: { use_ferry: 0, use_primary: 0, top_speed: QUIET_TOP_SPEED_KMH },
    });
  });

  const unpavedMiddle = fakeRoute([
    { way_id: 1, km: 0.3, unpaved: true },
    { way_id: 2, km: 1 },
    { way_id: 3, km: 0.4, unpaved: true },
    { way_id: 4, km: 1 },
    { way_id: 5, km: 0.2, unpaved: true },
  ]);
  const pavedDetour = fakeRoute(
    [
      { way_id: 1, km: 0.3, unpaved: true },
      { way_id: 2, km: 1 },
      { way_id: 6, km: 0.8 },
      { way_id: 4, km: 1 },
      { way_id: 5, km: 0.2, unpaved: true },
    ],
    undefined,
    0.002,
  );

  it("excludes interior unpaved edges and leaves the unpaved start and end alone", async () => {
    const { valhalla, result } = plan((body) => (body.exclude_locations ? pavedDetour : unpavedMiddle), request({ avoid: { unpaved: true } }));
    const { naviscoot } = await result;
    const [a, b] = [unpavedMiddle.coords[2]!, unpavedMiddle.coords[3]!];
    expect(valhalla.calls[1]?.exclude_locations).toEqual([{ lat: (a[0] + b[0]) / 2, lon: (a[1] + b[1]) / 2 }]);
    expect(valhalla.calls).toHaveLength(2);
    expect(naviscoot.avoid_unpaved).toEqual({ converged: true, remaining_m: 0 });
    expect(naviscoot.verified_only).toBeUndefined();
  });

  it("reports the unpaved metres left when no paved alternative exists", async () => {
    const { result } = plan(
      (body) => (body.exclude_locations ? new ValhallaError("No path could be found", 400, 442) : unpavedMiddle),
      request({ avoid: { unpaved: true } }),
    );
    expect((await result).naviscoot.avoid_unpaved).toEqual({ converged: false, remaining_m: 400 });
  });

  it("removes unverified paths before unpaved ones and keeps the verified route when the unpaved round fails", async () => {
    const unverifiedAndUnpaved = fakeRoute([
      { way_id: 1, km: 1 },
      { way_id: 20, use: "cycleway", km: 0.5 },
      { way_id: 3, km: 0.4, unpaved: true },
      { way_id: 2, km: 1 },
    ]);
    const verifiedButUnpaved = fakeRoute(
      [
        { way_id: 1, km: 1 },
        { way_id: 7, km: 0.6 },
        { way_id: 3, km: 0.4, unpaved: true },
        { way_id: 2, km: 1 },
      ],
      undefined,
      0.002,
    );
    const { valhalla, result } = plan((body) => {
      const excluded = (body.exclude_locations as unknown[] | undefined)?.length ?? 0;
      if (excluded === 0) return unverifiedAndUnpaved;
      if (excluded === 1) return verifiedButUnpaved;
      return new ValhallaError("No path could be found", 400, 442);
    }, request({ verifiedOnly: true, avoid: { unpaved: true } }));
    const { naviscoot } = await result;
    expect((valhalla.calls[1]?.exclude_locations as unknown[]).length).toBe(1);
    expect((valhalla.calls[2]?.exclude_locations as unknown[]).length).toBe(2);
    expect(naviscoot.length_m).toBe(3000);
    expect(naviscoot.totals_m.unverified).toBe(0);
    expect(naviscoot.verified_only).toEqual({ requests: 3, excluded_points: 1, converged: true });
    expect(naviscoot.avoid_unpaved).toEqual({ converged: false, remaining_m: 400 });
  });

  it("falls back to the last verified route when avoiding unpaved brings an unverified path back", async () => {
    const clean = fakeRoute([
      { way_id: 1, km: 1 },
      { way_id: 3, km: 0.4, unpaved: true },
      { way_id: 2, km: 1 },
    ]);
    const backOnUnverified = fakeRoute(
      [
        { way_id: 1, km: 1 },
        { way_id: 20, use: "cycleway", km: 0.5 },
        { way_id: 2, km: 1 },
      ],
      undefined,
      0.002,
    );
    const { result } = plan((body) => {
      const excluded = (body.exclude_locations as unknown[] | undefined)?.length ?? 0;
      if (excluded === 0) return clean;
      if (excluded === 1) return backOnUnverified;
      return new ValhallaError("No path could be found", 400, 442);
    }, request({ verifiedOnly: true, avoid: { unpaved: true } }));
    const { naviscoot } = await result;
    expect(naviscoot.length_m).toBe(2400);
    expect(naviscoot.totals_m.unverified).toBe(0);
    expect(naviscoot.verified_only).toMatchObject({ requests: 3, excluded_points: 0, converged: true });
    expect(naviscoot.avoid_unpaved).toEqual({ converged: false, remaining_m: 400 });
  });
});

describe("quiet profile", () => {
  const isQuietCall = (body: ValhallaBody) =>
    (body.costing_options as { motor_scooter?: { top_speed?: number } } | undefined)?.motor_scooter?.top_speed === QUIET_TOP_SPEED_KMH;
  const busy = fakeRoute([
    { way_id: 1, km: 1 },
    { way_id: 50, km: 2, road_class: "primary" },
    { way_id: 2, km: 1 },
  ]);
  const quiet = fakeRoute(
    [
      { way_id: 1, km: 1 },
      { way_id: 60, km: 1.2, road_class: "residential" },
      { way_id: 61, km: 1.2, road_class: "residential" },
      { way_id: 2, km: 1 },
    ],
    undefined,
    0.002,
  );

  it("re-traces the quiet route with the default costing for its times and instructions", async () => {
    const { valhalla, result } = plan(() => quiet, request({ avoid: { main_roads: true }, format: "osrm" }));
    const { response, naviscoot } = await result;
    expect(valhalla.traced).toEqual([
      {
        encoded_polyline: quiet.shape,
        shape_match: "edge_walk",
        costing: "motor_scooter",
        directions_options: { units: "kilometers", language: "nl-NL" },
        format: "osrm",
        banner_instructions: true,
        voice_instructions: true,
      },
    ]);
    const [route] = response.routes as { duration: number; confidence?: number }[];
    expect(route?.duration).toBeCloseTo(4.4 * FAKE_TRACED_SECONDS_PER_KM);
    expect(route).not.toHaveProperty("confidence");
    expect(naviscoot.profile).toBe("quiet");
    expect(naviscoot.main_road_m).toBe(0);
  });

  it("re-traces each leg of a quiet trip with stops and joins them", async () => {
    const legs = fakeLegs([[{ way_id: 1, km: 1 }], [{ way_id: 2, km: 2 }]]);
    const { valhalla, result } = plan(() => legs, request({ avoid: { main_roads: true }, waypoints: [{ lat: 52.1, lon: 5.1 }] }));
    const { response, naviscoot } = await result;
    expect(valhalla.traced.map((b) => b.encoded_polyline)).toEqual(legs.legs.map((l) => l.shape));
    const trip = (response as { trip: { legs: unknown[]; summary: { length: number; time: number } } }).trip;
    expect(trip.legs).toHaveLength(2);
    expect(trip.summary).toMatchObject({ length: 3, time: 3 * FAKE_TRACED_SECONDS_PER_KM });
    expect(naviscoot.legs?.map((l) => [l.start_shape_index, l.end_shape_index])).toEqual([
      [0, 1],
      [1, 2],
    ]);
  });

  it("falls back to the fastest route when the quiet route cannot be re-traced", async () => {
    const { valhalla, result } = plan(() => busy, request({ avoid: { main_roads: true } }));
    valhalla.traceRoute = async () => {
      throw new ValhallaError("valhalla trace_route 400: no match", 400);
    };
    const { naviscoot } = await result;
    expect(valhalla.calls.filter((c) => !isQuietCall(c))).toHaveLength(1);
    expect(naviscoot.profile).toBe("fastest");
  });

  it("offers the quiet route as the first alternative to the fastest one", async () => {
    const { result } = plan(
      (body) => (isAlternatesCall(body) ? [busy] : isQuietCall(body) ? quiet : busy),
      request({ alternatives: 2, format: "osrm" }),
    );
    const { response, naviscoot } = await result;
    expect(naviscoot.profile).toBe("fastest");
    expect(naviscoot.main_road_m).toBe(2000);
    expect(naviscoot.alternates?.map((a) => [a.profile, a.main_road_m])).toEqual([["quiet", 0]]);
    expect((response.routes as { duration?: number }[]).map((r) => r.duration)).toEqual([undefined, 4.4 * FAKE_TRACED_SECONDS_PER_KM]);
  });

  it("offers the fastest route as the alternative when quiet is requested", async () => {
    const { result } = plan(
      (body) => (isAlternatesCall(body) ? [busy] : isQuietCall(body) ? quiet : busy),
      request({ alternatives: 2, avoid: { main_roads: true } }),
    );
    const { naviscoot } = await result;
    expect(naviscoot.profile).toBe("quiet");
    expect(naviscoot.alternates?.map((a) => a.profile)).toEqual(["fastest"]);
  });

  it("drops the quiet route when it is the fastest route", async () => {
    const { result } = plan(() => busy, request({ alternatives: 2 }));
    const { naviscoot } = await result;
    expect(naviscoot.alternates).toEqual([]);
  });
});

describe("fastest guard", () => {
  const scenic = fakeRoute([
    { way_id: 1, km: 1 },
    { way_id: 70, use: "cycleway", km: 3 },
    { way_id: 2, km: 1 },
  ]);
  const direct = fakeRoute(
    [
      { way_id: 1, km: 1 },
      { way_id: 71, km: 2, road_class: "unclassified" },
      { way_id: 2, km: 1 },
    ],
    undefined,
    0.002,
  );
  const candidates: Costing[] = [{ speed_penalty_factor: 0 }, { shortest: true }];
  const motorScooter = (body: ValhallaBody) => (body.costing_options as { motor_scooter?: Record<string, unknown> } | undefined)?.motor_scooter;
  const isProbe = (body: ValhallaBody) => body.directions_type === "none";
  const run = (defaultSeconds: number, candidateSeconds: number, req: RouteRequest) => {
    const valhalla = fakeValhalla((body) => (motorScooter(body)?.speed_penalty_factor === 0 ? direct : scenic));
    const route = valhalla.route.bind(valhalla);
    valhalla.route = async (body) => {
      const response = await route(body);
      const options = motorScooter(body);
      const seconds = options?.speed_penalty_factor === 0 ? candidateSeconds : options?.shortest ? 9999 : defaultSeconds;
      if (body.format === "osrm") {
        return { ...response, routes: (response.routes as Record<string, unknown>[]).map((r) => ({ ...r, duration: seconds })) };
      }
      const trip = response.trip as { summary: Record<string, unknown> };
      return { ...response, trip: { ...trip, summary: { ...trip.summary, time: seconds } } };
    };
    return { valhalla, result: planRoute({ valhalla, fused, maxVerifiedRequests: 5, fastestCandidates: candidates }, req, NOW) };
  };
  const routed = (calls: ValhallaBody[]) => calls.filter((c) => !isProbe(c));

  it("allows 10% of the quickest time, at least 30 s and at most 3 min", () => {
    expect(fastestSlackS(100)).toBe(30);
    expect(fastestSlackS(600)).toBe(60);
    expect(fastestSlackS(1800)).toBe(180);
    expect(fastestSlackS(30_000)).toBe(180);
  });

  it("probes every candidate and keeps the default when it is at most the slack slower", async () => {
    const { valhalla, result } = run(1100, 1000, request());
    const { naviscoot } = await result;
    expect(valhalla.calls.filter(isProbe).map(motorScooter)).toEqual(candidates);
    expect(routed(valhalla.calls)).toHaveLength(1);
    expect(routed(valhalla.calls)[0]).not.toHaveProperty("costing_options");
    expect(naviscoot.stretches.map((s) => s.class)).toContain("moped_path");
  });

  it("plans the quickest candidate when the default is more than the slack slower", async () => {
    const { valhalla, result } = run(1101, 1000, request({ avoid: { ferries: true }, format: "osrm" }));
    const { response, naviscoot } = await result;
    expect(routed(valhalla.calls).map(motorScooter)).toEqual([{ use_ferry: 0 }, { use_ferry: 0, speed_penalty_factor: 0 }]);
    expect((response.routes as { duration: number }[])[0]?.duration).toBe(1000);
    expect(naviscoot.profile).toBe("fastest");
    expect(naviscoot.stretches.map((s) => s.class)).toEqual(["carriageway"]);
  });

  it("probes in the native format without directions", async () => {
    const { valhalla, result } = run(1000, 1000, request({ format: "osrm" }));
    await result;
    for (const probe of valhalla.calls.filter(isProbe)) {
      expect(probe).not.toHaveProperty("format");
      expect(probe).not.toHaveProperty("banner_instructions");
    }
  });

  it("leaves the shortest candidate out when ferries are avoided", async () => {
    const { valhalla, result } = run(1000, 1000, request({ avoid: { ferries: true } }));
    await result;
    expect(valhalla.calls.filter(isProbe).map(motorScooter)).toEqual([{ use_ferry: 0, speed_penalty_factor: 0 }]);
  });

  it("does not probe for the quiet profile", async () => {
    const { valhalla, result } = run(1000, 1000, request({ avoid: { main_roads: true } }));
    await result;
    expect(valhalla.calls.filter(isProbe)).toEqual([]);
  });
});
