import { fileURLToPath } from "node:url";

export interface Config {
  apiKey: string;
  valhallaUrl: string;
  fusedCsvPath: string;
  reportsPath: string;
  host: string;
  port: number;
  maxVerifiedRequests: number;
}

const fromApiDir = (relative: string) => fileURLToPath(new URL(`../${relative}`, import.meta.url));

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const apiKey = env.API_KEY?.trim();
  if (!apiKey) throw new Error("API_KEY is required");
  return {
    apiKey,
    valhallaUrl: env.VALHALLA_URL ?? "http://127.0.0.1:8002",
    fusedCsvPath: env.FUSED_ACCESS_CSV ?? fromApiDir("../data/build/fused_access.csv"),
    reportsPath: env.REPORTS_PATH ?? fromApiDir("data/reports.jsonl"),
    host: env.HOST ?? "127.0.0.1",
    port: Number(env.PORT ?? 8080),
    maxVerifiedRequests: Number(env.MAX_VERIFIED_REQUESTS ?? 5),
  };
}
