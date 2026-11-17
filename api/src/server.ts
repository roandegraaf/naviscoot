import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { loadFused } from "./fused.js";
import { ReportStore } from "./reports.js";
import { FASTEST_CANDIDATES } from "./route.js";
import { httpValhalla } from "./valhalla.js";

const config = loadConfig();
const fused = await loadFused(config.fusedCsvPath);
const reports = await ReportStore.open(config.reportsPath);
const app = buildApp({
  apiKey: config.apiKey,
  valhalla: httpValhalla(config.valhallaUrl),
  fused,
  reports,
  maxVerifiedRequests: config.maxVerifiedRequests,
  fastestCandidates: FASTEST_CANDIDATES,
  logger: true,
});

app.log.info(
  { fusedWays: fused.size, reports: reports.list().length, valhalla: config.valhallaUrl, reportsPath: config.reportsPath },
  "naviscoot api starting",
);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    void app.close().then(() => process.exit(0));
  });
}

await app.listen({ host: config.host, port: config.port });
