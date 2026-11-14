import { readFile } from "node:fs/promises";

export type FusedStatus = "allowed" | "forbidden" | "unknown";
export type FusedAccess = ReadonlyMap<number, FusedStatus>;

const STATUSES = new Set<string>(["allowed", "forbidden", "unknown"]);

export function parseFused(csv: string): Map<number, FusedStatus> {
  const lines = csv.split(/\r?\n/);
  const header = lines[0]?.split(",") ?? [];
  const wayCol = header.indexOf("way_id");
  const statusCol = header.indexOf("status");
  if (wayCol < 0 || statusCol < 0) throw new Error("fused access CSV needs way_id and status columns");
  const fused = new Map<number, FusedStatus>();
  for (const line of lines.slice(1)) {
    if (!line) continue;
    const cols = line.split(",");
    const status = cols[statusCol] ?? "";
    if (!STATUSES.has(status)) throw new Error(`unexpected fused status "${status}" in: ${line}`);
    fused.set(Number(cols[wayCol]), status as FusedStatus);
  }
  return fused;
}

export async function loadFused(path: string): Promise<Map<number, FusedStatus>> {
  return parseFused(await readFile(path, "utf8"));
}
