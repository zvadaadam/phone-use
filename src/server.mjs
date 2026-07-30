import { createReadStream } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer, WebSocket } from "ws";
import { validateControl } from "./control.mjs";
import { MirrorProcess } from "./mirror-process.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PUBLIC = join(ROOT, "public");
const args = parseArgs(process.argv.slice(2));
const mirror = new MirrorProcess();
const streamClients = new Set();
const socketClients = new Set();
const recentLogs = [];

const securityHeaders = {
  "Cache-Control": "no-store",
  "Content-Security-Policy":
    "default-src 'self'; img-src 'self' blob:; style-src 'self'; script-src 'self'; connect-src 'self' ws: wss:",
  "Cross-Origin-Opener-Policy": "same-origin",
  "X-Content-Type-Options": "nosniff",
};

const server = createServer((request, response) => {
  const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);

  if (request.method === "GET" && url.pathname === "/stream.mjpeg") {
    response.writeHead(200, {
      ...securityHeaders,
      "Content-Type": "multipart/x-mixed-replace; boundary=frame",
      Connection: "keep-alive",
    });
    streamClients.add(response);
    if (mirror.latestFrame) writeMjpeg(response, mirror.latestFrame);
    response.on("close", () => streamClients.delete(response));
    response.on("error", () => streamClients.delete(response));
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/status") {
    sendJson(response, 200, { ...mirror.status, logs: recentLogs.slice(-20) });
    return;
  }

  if (request.method !== "GET" && request.method !== "HEAD") {
    sendJson(response, 405, { error: "Method not allowed" });
    return;
  }

  serveStatic(url.pathname, response, request.method === "HEAD");
});

const webSockets = new WebSocketServer({ noServer: true });
server.on("upgrade", (request, socket, head) => {
  const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);
  if (url.pathname !== "/ws") {
    socket.destroy();
    return;
  }
  webSockets.handleUpgrade(request, socket, head, (webSocket) => {
    webSockets.emit("connection", webSocket);
  });
});

webSockets.on("connection", (socket) => {
  socketClients.add(socket);
  sendSocket(socket, { type: "status", payload: mirror.status });
  for (const line of recentLogs.slice(-12)) {
    sendSocket(socket, { type: "log", payload: line });
  }

  socket.on("message", (data, isBinary) => {
    if (isBinary) {
      sendSocket(socket, { type: "error", payload: "Binary control messages are not supported" });
      return;
    }
    try {
      const control = validateControl(JSON.parse(data.toString("utf8")));
      if (control.type === "restart") {
        mirror.restart();
      } else {
        mirror.send(control);
      }
    } catch (error) {
      sendSocket(socket, { type: "error", payload: error.message });
    }
  });

  socket.on("close", () => socketClients.delete(socket));
  socket.on("error", () => socketClients.delete(socket));
});

mirror.on("frame", (frame) => {
  for (const response of streamClients) {
    if (!response.writableNeedDrain) writeMjpeg(response, frame);
  }
});
mirror.on("status", (status) => broadcast({ type: "status", payload: status }));
mirror.on("log", (line) => {
  recentLogs.push(line);
  if (recentLogs.length > 100) recentLogs.shift();
  broadcast({ type: "log", payload: line });
});

server.listen(args.port, args.host, () => {
  console.log(`Mirror Relay: http://${args.host}:${args.port}`);
  if (args.host !== "127.0.0.1" && args.host !== "localhost") {
    console.warn("Warning: the bridge has no authentication. Keep it on a trusted network.");
  }
  mirror.start();
});

function serveStatic(pathname, response, headOnly = false) {
  const requested = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const safePath = normalize(requested);
  if (safePath.startsWith("..") || safePath.includes("\0")) {
    sendJson(response, 400, { error: "Invalid path" });
    return;
  }
  const filePath = join(PUBLIC, safePath);
  const mime = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
  }[extname(filePath)] || "application/octet-stream";

  const stream = createReadStream(filePath);
  stream.once("open", () => {
    response.writeHead(200, { ...securityHeaders, "Content-Type": mime });
    if (headOnly) {
      stream.destroy();
      response.end();
    } else {
      stream.pipe(response);
    }
  });
  stream.once("error", () => sendJson(response, 404, { error: "Not found" }));
}

function writeMjpeg(response, jpeg) {
  response.write(`--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n`);
  response.write(jpeg);
  response.write("\r\n");
}

function sendJson(response, statusCode, value) {
  response.writeHead(statusCode, {
    ...securityHeaders,
    "Content-Type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify(value));
}

function sendSocket(socket, value) {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value));
}

function broadcast(value) {
  for (const socket of socketClients) sendSocket(socket, value);
}

function parseArgs(values) {
  const result = { host: "127.0.0.1", port: 3200 };
  for (let index = 0; index < values.length; index += 1) {
    if (values[index] === "--host" && values[index + 1]) result.host = values[++index];
    else if (values[index] === "--port" && values[index + 1]) {
      const port = Number(values[++index]);
      if (Number.isInteger(port) && port > 0 && port <= 65_535) result.port = port;
    }
  }
  return result;
}

function shutdown() {
  mirror.stop();
  for (const response of streamClients) response.destroy();
  for (const socket of socketClients) socket.terminate();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1_000).unref();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
