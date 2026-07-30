import { containedFrame } from "./geometry.js";

const elements = {
  body: document.body,
  statusPill: document.querySelector("#status-pill"),
  statusLabel: document.querySelector("#status-label"),
  fps: document.querySelector("#fps-value"),
  size: document.querySelector("#size-value"),
  bridgeDetail: document.querySelector("#bridge-detail"),
  emptyTitle: document.querySelector("#empty-title"),
  emptyCopy: document.querySelector("#empty-copy"),
  stream: document.querySelector("#stream"),
  screenInput: document.querySelector("#screen-input"),
  restart: document.querySelector("#restart-button"),
  text: document.querySelector("#text-input"),
  sendText: document.querySelector("#send-text"),
  log: document.querySelector("#event-log"),
  clearLog: document.querySelector("#clear-log"),
  latency: document.querySelector("#latency-label"),
};

const token = new URLSearchParams(location.search).get("token") || "";
const authQuery = token ? `?token=${encodeURIComponent(token)}` : "";
let statusTimer;
let pendingMove;
let pointerActive = false;
let captureSize = null;

if (token) history.replaceState({}, "", "/");
elements.stream.src = `/stream.mjpeg${authQuery}`;
connect();

elements.restart.addEventListener("click", async () => {
  await post("/api/session/open");
  addLog("Opening iPhone session");
});

document.querySelectorAll("[data-shortcut]").forEach((button) => {
  button.addEventListener("click", () => {
    send({ type: "shortcut", name: button.dataset.shortcut });
    addLog(`${button.textContent.trim()} command sent`);
  });
});

elements.sendText.addEventListener("click", submitText);
elements.text.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") submitText();
});
elements.clearLog.addEventListener("click", () => {
  elements.log.replaceChildren();
});

elements.screenInput.addEventListener("pointerdown", (event) => {
  if (!sendPointer("down", event)) return;
  pointerActive = true;
  elements.screenInput.setPointerCapture(event.pointerId);
});
elements.screenInput.addEventListener("pointermove", (event) => {
  if (!pointerActive) return;
  pendingMove = event;
  if (!elements.screenInput.dataset.moveScheduled) {
    elements.screenInput.dataset.moveScheduled = "true";
    requestAnimationFrame(() => {
      if (pendingMove) sendPointer("move", pendingMove);
      pendingMove = null;
      delete elements.screenInput.dataset.moveScheduled;
    });
  }
});
elements.screenInput.addEventListener("pointerup", finishPointer);
elements.screenInput.addEventListener("pointercancel", finishPointer);
elements.screenInput.addEventListener("contextmenu", (event) => event.preventDefault());

function connect() {
  clearInterval(statusTimer);
  if (!token) {
    document.querySelector('[data-step="browser"]').dataset.ready = "false";
    addLog("Open this dashboard from the Mirror Relay menu to authorize it");
    return;
  }
  pollStatus();
  statusTimer = setInterval(pollStatus, 1_000);
}

async function pollStatus() {
  try {
    const response = await fetch(`/api/status${authQuery}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`Status ${response.status}`);
    updateStatus(await response.json());
    document.querySelector('[data-step="browser"]').dataset.ready = "true";
  } catch {
    document.querySelector('[data-step="browser"]').dataset.ready = "false";
  }
}

async function send(value) {
  await post("/api/act", value);
}

async function post(path, value) {
  try {
    const response = await fetch(`${path}${authQuery}`, {
      method: "POST",
      headers: value ? { "Content-Type": "application/json" } : {},
      body: value ? JSON.stringify(value) : undefined,
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || `Request ${response.status}`);
    return payload;
  } catch (error) {
    addLog(`Bridge error: ${error.message}`);
    return null;
  }
}

function sendPointer(phase, event) {
  const rect = elements.screenInput.getBoundingClientRect();
  const frame = containedFrame(rect, captureSize);
  let x = (event.clientX - frame.left) / frame.width;
  let y = (event.clientY - frame.top) / frame.height;
  if (phase === "up") {
    x = Math.min(1, Math.max(0, x));
    y = Math.min(1, Math.max(0, y));
  } else if (x < 0 || x > 1 || y < 0 || y > 1) {
    return false;
  }
  void send({ type: "pointer", phase, x, y });
  return true;
}

function finishPointer(event) {
  if (!pointerActive) return;
  pointerActive = false;
  sendPointer("up", event);
}

function submitText() {
  const text = elements.text.value;
  if (!text.trim()) return;
  send({ type: "type", text });
  elements.text.value = "";
  addLog(`Sent ${text.length} character${text.length === 1 ? "" : "s"}`);
}

function updateStatus(status) {
  const live = status.phase === "streaming" && status.fps > 0;
  if (status.width && status.height) {
    captureSize = { width: status.width, height: status.height };
  }
  elements.body.dataset.live = String(live);
  elements.statusPill.dataset.status = status.phase;
  elements.statusLabel.textContent = friendlyPhase(status.phase);
  elements.fps.textContent = `${status.fps || 0} fps`;
  elements.size.textContent = status.width && status.height
    ? `${status.width}×${status.height}`
    : "—";
  elements.bridgeDetail.textContent = status.message || "Waiting";
  elements.latency.textContent = live ? "live packets" : "awaiting frames";

  document.querySelector('[data-step="phone"]').dataset.ready = String(live);
  document.querySelector('[data-step="continuity"]').dataset.ready = String(live);
  document.querySelector('[data-step="bridge"]').dataset.ready = String(live);

  if (!live) {
    elements.emptyTitle.textContent = titleForPhase(status.phase);
    elements.emptyCopy.textContent = status.message || "Keep the iPhone nearby, powered on, and locked.";
  }
}

function addLog(message) {
  const line = document.createElement("p");
  const time = document.createElement("time");
  const text = document.createElement("span");
  time.textContent = new Date().toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  text.textContent = message;
  line.append(time, text);
  elements.log.prepend(line);
  while (elements.log.children.length > 30) elements.log.lastElementChild.remove();
}

function friendlyPhase(phase) {
  return {
    starting: "Starting",
    waiting: "Waiting",
    streaming: "Live",
    permission: "Permission",
    launching: "Launching",
    setup: "Setup",
    missing: "Build needed",
    error: "Error",
    stopped: "Stopped",
  }[phase] || phase;
}

function titleForPhase(phase) {
  return {
    permission: "Permission required",
    launching: "Starting fallback automation",
    setup: "One-time fallback setup required",
    missing: "Build the native bridge",
    error: "Bridge error",
    stopped: "Bridge stopped",
  }[phase] || "Waiting for iPhone Mirroring";
}
