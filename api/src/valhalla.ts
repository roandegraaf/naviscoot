export interface TraceEdge {
  way_id: number;
  length: number;
  use: string;
  begin_shape_index: number;
  end_shape_index: number;
  speed_limit?: number;
}

export type ValhallaBody = Record<string, unknown>;
export type ValhallaResponse = Record<string, unknown>;

export interface ValhallaClient {
  route(body: ValhallaBody): Promise<ValhallaResponse>;
  edgeWalk(encodedPolyline: string): Promise<TraceEdge[]>;
  status(): Promise<boolean>;
}

export class ValhallaError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number,
    readonly errorCode?: number,
  ) {
    super(message);
  }

  get unavailable(): boolean {
    return this.httpStatus === 0 || this.httpStatus >= 500;
  }
}

const EDGE_ATTRIBUTES = ["edge.way_id", "edge.length", "edge.use", "edge.begin_shape_index", "edge.end_shape_index", "edge.speed_limit"];

export function httpValhalla(baseUrl: string, timeoutMs = 60_000): ValhallaClient {
  const url = baseUrl.replace(/\/+$/, "");

  async function post(action: string, body: ValhallaBody): Promise<ValhallaResponse> {
    let res: Response;
    try {
      res = await fetch(`${url}/${action}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      throw new ValhallaError(`valhalla ${action} unreachable: ${(err as Error).message}`, 0);
    }
    const data = (await res.json().catch(() => ({}))) as ValhallaResponse;
    if (!res.ok) {
      const message = typeof data.error === "string" ? data.error : res.statusText;
      const code = typeof data.error_code === "number" ? data.error_code : undefined;
      throw new ValhallaError(`valhalla ${action} ${res.status}: ${message}`, res.status, code);
    }
    return data;
  }

  return {
    route: (body) => post("route", body),
    async edgeWalk(encodedPolyline) {
      const data = await post("trace_attributes", {
        encoded_polyline: encodedPolyline,
        shape_match: "edge_walk",
        costing: "motor_scooter",
        filters: { attributes: EDGE_ATTRIBUTES, action: "include" },
      });
      return (data.edges as Partial<TraceEdge>[]).map((e) => ({
        way_id: e.way_id ?? 0,
        length: e.length ?? 0,
        use: e.use ?? "",
        begin_shape_index: e.begin_shape_index ?? 0,
        end_shape_index: e.end_shape_index ?? 0,
        ...(typeof e.speed_limit === "number" ? { speed_limit: e.speed_limit } : {}),
      }));
    },
    async status() {
      try {
        const res = await fetch(`${url}/status`, { signal: AbortSignal.timeout(2_000) });
        return res.ok;
      } catch {
        return false;
      }
    },
  };
}
