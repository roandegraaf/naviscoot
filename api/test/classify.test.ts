import { describe, expect, it } from "vitest";
import { classifyRoute, edgeClass, roundToTotal, speedLimits } from "../src/classify.js";
import { type FusedStatus, parseFused } from "../src/fused.js";
import { fakeRoute } from "./fake-valhalla.js";

const fused = new Map<number, FusedStatus>([
  [10, "allowed"],
  [20, "unknown"],
  [30, "forbidden"],
]);

const edge = (way_id: number, use = "road") => ({ way_id, use, length: 0.1, begin_shape_index: 0, end_shape_index: 1 });

describe("edgeClass", () => {
  it("maps fused unknown to unverified and fused allowed to moped path", () => {
    expect(edgeClass(edge(20, "cycleway"), fused)).toBe("unverified");
    expect(edgeClass(edge(10, "cycleway"), fused)).toBe("moped_path");
  });

  it("treats other cycleways and paths as moped path and everything else as carriageway", () => {
    expect(edgeClass(edge(99, "cycleway"), fused)).toBe("moped_path");
    expect(edgeClass(edge(99, "path"), fused)).toBe("moped_path");
    expect(edgeClass(edge(99, "road"), fused)).toBe("carriageway");
    expect(edgeClass(edge(99, "track"), fused)).toBe("carriageway");
  });

  it("keeps a fused-forbidden way visible instead of calling it a moped path", () => {
    expect(edgeClass(edge(30, "cycleway"), fused)).toBe("forbidden");
  });
});

describe("speedLimits", () => {
  it("gives the carriageway 45 and a moped path its graph limit, in runs covering the whole route", () => {
    const route = fakeRoute([
      { way_id: 1, km: 0.2, speed_limit: 80 },
      { way_id: 2, km: 0.3, speed_limit: 30 },
      { way_id: 10, use: "cycleway", km: 0.4, speed_limit: 40 },
      { way_id: 99, use: "cycleway", km: 0.1, speed_limit: 40 },
      { way_id: 20, use: "cycleway", km: 0.25, speed_limit: 30 },
      { way_id: 3, km: 0.5 },
    ]);
    expect(speedLimits(route.edges, fused)).toEqual([
      { start_shape_index: 0, end_shape_index: 2, kmh: 45 },
      { start_shape_index: 2, end_shape_index: 4, kmh: 40 },
      { start_shape_index: 4, end_shape_index: 5, kmh: 30 },
      { start_shape_index: 5, end_shape_index: 6, kmh: 45 },
    ]);
  });

  it("assumes 30 on a path whose graph limit is missing or not a moped path limit", () => {
    const route = fakeRoute([
      { way_id: 99, use: "cycleway", km: 0.1 },
      { way_id: 10, use: "cycleway", km: 0.1, speed_limit: 15 },
    ]);
    expect(speedLimits(route.edges, fused)).toEqual([{ start_shape_index: 0, end_shape_index: 2, kmh: 30 }]);
  });

  it("is part of every classification", () => {
    const route = fakeRoute([{ way_id: 1, km: 0.2 }]);
    expect(classifyRoute(route.edges, 200, fused).speed_limits).toEqual([{ start_shape_index: 0, end_shape_index: 1, kmh: 45 }]);
  });
});

describe("classifyRoute", () => {
  it("adds up the metres on motorway, trunk, primary and secondary roads", () => {
    const route = fakeRoute([
      { way_id: 1, km: 0.4, road_class: "primary" },
      { way_id: 2, km: 0.3, road_class: "secondary" },
      { way_id: 3, km: 0.2, road_class: "tertiary" },
      { way_id: 4, km: 0.1, road_class: "residential" },
    ]);
    expect(classifyRoute(route.edges, 1000, new Map()).main_road_m).toBe(700);
  });

  it("merges consecutive edges of one class into stretches with shape indices and way ids", () => {
    const route = fakeRoute([
      { way_id: 1, km: 0.2 },
      { way_id: 2, km: 0.3 },
      { way_id: 99, use: "cycleway", km: 0.1 },
      { way_id: 10, use: "cycleway", km: 0.4 },
      { way_id: 20, use: "cycleway", km: 0.25 },
      { way_id: 20, use: "cycleway", km: 0.25 },
      { way_id: 3, km: 0.5 },
    ]);
    const c = classifyRoute(route.edges, route.lengthKm * 1000, fused);
    expect(c.stretches.map((s) => [s.class, s.start_shape_index, s.end_shape_index, s.length_m, s.way_ids])).toEqual([
      ["carriageway", 0, 2, 500, [1, 2]],
      ["moped_path", 2, 4, 500, [99, 10]],
      ["unverified", 4, 6, 500, [20]],
      ["carriageway", 6, 7, 500, [3]],
    ]);
    expect(c.totals_m).toEqual({ carriageway: 1000, moped_path: 500, unverified: 500, forbidden: 0 });
    expect(c.warnings).toEqual([]);
  });

  it("scales edge lengths so the totals add up exactly to the route length in metres", () => {
    const route = fakeRoute([
      { way_id: 1, km: 0.3331 },
      { way_id: 20, use: "cycleway", km: 0.3332 },
      { way_id: 2, use: "cycleway", km: 0.3333 },
      { way_id: 3, km: 0.0003 },
    ]);
    const routeM = 1000.6;
    const c = classifyRoute(route.edges, routeM, fused);
    const sum = Object.values(c.totals_m).reduce((a, b) => a + b, 0);
    expect(c.length_m).toBe(1001);
    expect(sum).toBe(1001);
    expect(c.stretches.reduce((a, s) => a + s.length_m, 0)).toBe(1001);
    expect(c.edge_length_m).toBe(1000);
  });

  it("warns when the route crosses a fused-forbidden way or edge lengths drift", () => {
    const route = fakeRoute([
      { way_id: 1, km: 0.5 },
      { way_id: 30, use: "cycleway", km: 0.5 },
    ]);
    const c = classifyRoute(route.edges, 1100, fused);
    expect(c.totals_m.forbidden).toBeGreaterThan(0);
    expect(c.warnings).toHaveLength(2);
    expect(c.warnings[0]).toContain("30");
  });
});

describe("roundToTotal", () => {
  it("distributes the remainder to the largest fractions", () => {
    expect(roundToTotal([1.6, 1.3, 1.1], 4)).toEqual([2, 1, 1]);
    expect(roundToTotal([0.5, 0.5], 1)).toHaveLength(2);
  });
});

describe("parseFused", () => {
  it("reads way_id and status and rejects unknown statuses", () => {
    const map = parseFused("way_id,status,source,source_id,date\n5,allowed,osm,x,2022-01-01\n6,unknown,,,\n");
    expect([...map]).toEqual([
      [5, "allowed"],
      [6, "unknown"],
    ]);
    expect(() => parseFused("way_id,status\n5,maybe\n")).toThrow();
  });
});
