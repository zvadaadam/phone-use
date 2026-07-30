import http from "node:http";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const screenshot =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl94AAAAASUVORK5CYII=";

function json(response, status, value) {
  const body = Buffer.from(JSON.stringify(value));
  response.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": body.length,
  });
  response.end(body);
}

async function readJSON(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

export function startMockWDA(port, onListen = () => {}) {
  const actions = [];
  const server = http.createServer(async (request, response) => {
    const url = new URL(request.url, `http://127.0.0.1:${port}`);
    const path = url.pathname;
    const body = await readJSON(request);

    if (request.method === "GET" && path === "/status") {
      return json(response, 200, {
        value: { ready: true, message: "Mock WebDriverAgent is ready" },
      });
    }
    if (request.method === "POST" && path === "/session") {
      return json(response, 200, {
        value: {
          sessionId: "mirror-relay-smoke",
          capabilities: { device: "iphone" },
        },
      });
    }
    if (
      request.method === "POST" &&
      path === "/session/mirror-relay-smoke/appium/settings"
    ) {
      return json(response, 200, { value: null });
    }
    if (request.method === "GET" && path === "/wda/screen") {
      return json(response, 200, {
        value: {
          screenSize: { width: 390, height: 844 },
          statusBarSize: { width: 390, height: 54 },
          scale: 3,
        },
      });
    }
    if (request.method === "GET" && path === "/screenshot") {
      return json(response, 200, { value: screenshot });
    }
    if (request.method === "GET" && path === "/source") {
      return json(response, 200, {
        value: {
          type: "XCUIElementTypeApplication",
          name: "Mock iPhone",
          children: [{ type: "XCUIElementTypeIcon", name: "Settings" }],
        },
      });
    }
    if (request.method === "GET" && path === "/test/state") {
      return json(response, 200, { actions });
    }
    if (
      request.method === "POST" &&
      (path.endsWith("/wda/tap") ||
        path.endsWith("/wda/dragfromtoforduration") ||
        path.endsWith("/wda/keys") ||
        path === "/wda/homescreen")
    ) {
      actions.push({ method: request.method, path, body });
      return json(response, 200, { value: null });
    }
    if (
      request.method === "DELETE" &&
      path === "/session/mirror-relay-smoke"
    ) {
      actions.push({ method: request.method, path, body });
      return json(response, 200, { value: null });
    }
    return json(response, 404, {
      value: { error: "unknown command", message: `${request.method} ${path}` },
    });
  });

  server.listen(port, "127.0.0.1", () => onListen(server));
  return server;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  const port = Number(process.env.MIRROR_RELAY_MOCK_WDA_PORT || 18100);
  const server = startMockWDA(port, () => {
    process.stdout.write(`Mock WebDriverAgent listening on 127.0.0.1:${port}\n`);
  });
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => server.close(() => process.exit(0)));
  }
}
