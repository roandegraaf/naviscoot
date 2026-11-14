import { createHash, timingSafeEqual } from "node:crypto";
import Fastify, { type FastifyInstance } from "fastify";
import type { FusedAccess } from "./fused.js";
import type { ReportInput, ReportStore } from "./reports.js";
import { type Point, planRoute, type RouteFormat } from "./route.js";
import { type ValhallaClient, ValhallaError } from "./valhalla.js";

export interface AppDeps {
  apiKey: string;
  valhalla: ValhallaClient;
  fused: FusedAccess;
  reports: ReportStore;
  maxVerifiedRequests: number;
  logger?: boolean;
}

interface RouteBody {
  origin: Point;
  destination: Point;
  verified_only: boolean;
  format: RouteFormat;
  language: string;
}

const point = {
  type: "object",
  required: ["lat", "lon"],
  additionalProperties: false,
  properties: {
    lat: { type: "number", minimum: -90, maximum: 90 },
    lon: { type: "number", minimum: -180, maximum: 180 },
  },
} as const;

const routeSchema = {
  body: {
    type: "object",
    required: ["origin", "destination"],
    additionalProperties: false,
    properties: {
      origin: point,
      destination: point,
      verified_only: { type: "boolean", default: false },
      format: { enum: ["valhalla", "osrm"], default: "valhalla" },
      language: { type: "string", pattern: "^[a-z]{2}(-[A-Z]{2})?$", default: "nl-NL" },
    },
  },
} as const;

const reportSchema = {
  body: {
    type: "object",
    required: ["lat", "lon"],
    additionalProperties: false,
    properties: {
      ...point.properties,
      time: { type: "string", format: "date-time" },
      note: { type: "string", maxLength: 2000 },
      route_id: { type: "string", maxLength: 100 },
    },
  },
} as const;

const PUBLIC_ROUTES = new Set(["/health"]);

function keyDigest(key: string): Buffer {
  return createHash("sha256").update(key).digest();
}

export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({ logger: deps.logger ?? false });
  const expectedKey = keyDigest(deps.apiKey);

  app.addHook("onRequest", async (request, reply) => {
    if (request.routeOptions.url && PUBLIC_ROUTES.has(request.routeOptions.url)) return;
    const given = request.headers["x-api-key"];
    if (typeof given !== "string" || !timingSafeEqual(keyDigest(given), expectedKey)) {
      reply.code(401).send({ error: "unauthorized" });
      return reply;
    }
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ValhallaError) {
      request.log.warn({ err: error }, "valhalla error");
      if (error.unavailable) return reply.code(502).send({ error: "valhalla_unavailable", message: error.message });
      return reply.code(422).send({ error: "no_route", message: error.message });
    }
    return reply.send(error);
  });

  app.get("/health", async () => ({ status: "ok", valhalla: await deps.valhalla.status() }));

  app.post<{ Body: RouteBody }>("/route", { schema: routeSchema }, async (request) => {
    const body = request.body;
    const result = await planRoute(
      { valhalla: deps.valhalla, fused: deps.fused, maxVerifiedRequests: deps.maxVerifiedRequests },
      {
        origin: body.origin,
        destination: body.destination,
        verifiedOnly: body.verified_only,
        format: body.format,
        language: body.language,
      },
    );
    return { ...result.response, naviscoot: result.naviscoot };
  });

  app.post<{ Body: ReportInput }>("/reports", { schema: reportSchema }, async (request, reply) => {
    const report = await deps.reports.add(request.body);
    return reply.code(201).send(report);
  });

  app.get("/reports", async () => ({ reports: deps.reports.list() }));

  return app;
}
