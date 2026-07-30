#!/usr/bin/env node

import { startMockWDA } from "./mock-wda.mjs";

const port = Number(process.env.MIRROR_RELAY_MOCK_WDA_PORT || 18100);
const server = startMockWDA(port, () => {
  process.stdout.write(
    `ServerURLHere->http://127.0.0.1:${port}<-ServerURLHere\n`,
  );
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
