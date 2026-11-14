import { randomUUID } from "node:crypto";
import { mkdir, open, readFile, truncate } from "node:fs/promises";
import { dirname } from "node:path";

export interface ReportInput {
  lat: number;
  lon: number;
  time?: string;
  note?: string;
  route_id?: string;
}

export interface Report {
  id: string;
  lat: number;
  lon: number;
  time: string;
  received_at: string;
  note?: string;
  route_id?: string;
}

export class ReportStore {
  private queue: Promise<unknown> = Promise.resolve();

  private constructor(
    private readonly path: string,
    private readonly reports: Report[],
  ) {}

  static async open(path: string): Promise<ReportStore> {
    await mkdir(dirname(path), { recursive: true });
    const buf = await readFile(path).catch((err: NodeJS.ErrnoException) => {
      if (err.code === "ENOENT") return Buffer.alloc(0);
      throw err;
    });
    const complete = buf.subarray(0, buf.lastIndexOf(0x0a) + 1);
    if (complete.length < buf.length) {
      // A crash mid-append leaves a partial last line; drop it so the next append starts on a fresh line.
      await truncate(path, complete.length);
    }
    const reports = complete
      .toString("utf8")
      .split("\n")
      .filter(Boolean)
      .map((line, i) => {
        try {
          return JSON.parse(line) as Report;
        } catch (err) {
          throw new Error(`corrupt report store ${path} at line ${i + 1}: ${(err as Error).message}`);
        }
      });
    return new ReportStore(path, reports);
  }

  list(): Report[] {
    return [...this.reports];
  }

  add(input: ReportInput, now = new Date()): Promise<Report> {
    const report: Report = {
      id: randomUUID(),
      lat: input.lat,
      lon: input.lon,
      time: input.time ? new Date(input.time).toISOString() : now.toISOString(),
      received_at: now.toISOString(),
      ...(input.note ? { note: input.note } : {}),
      ...(input.route_id ? { route_id: input.route_id } : {}),
    };
    const write = this.queue.then(() => this.append(report));
    this.queue = write.catch(() => undefined);
    return write;
  }

  private async append(report: Report): Promise<Report> {
    const file = await open(this.path, "a");
    try {
      await file.write(`${JSON.stringify(report)}\n`);
      await file.sync();
    } finally {
      await file.close();
    }
    this.reports.push(report);
    return report;
  }
}
