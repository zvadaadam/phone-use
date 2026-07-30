import { containedFrame, gestureCommand } from "./geometry.js";

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
  close: document.querySelector("#close-session"),
  text: document.querySelector("#text-input"),
  sendText: document.querySelector("#send-text"),
  log: document.querySelector("#event-log"),
  clearLog: document.querySelector("#clear-log"),
  latency: document.querySelector("#latency-label"),
};

let statusTimer;
let gesture;
let captureSize = null;
let authorizationReported = false;

connect();

elements.restart.addEventListener("click", async () => {
  await runButtonAction(elements.restart, async () => {
    await post("/api/session/open");
    addLog("iPhone session opened");
  });
});

elements.close.addEventListener("click", async () => {
  await runButtonAction(elements.close, async () => {
    await post("/api/session/close");
    addLog("iPhone session closed");
  });
});

document.querySelectorAll("[data-shortcut]").forEach((button) => {
  button.addEventListener("click", async () => {
    await runButtonAction(button, async () => {
      await send({ type: "shortcut", name: button.dataset.shortcut });
      addLog(`${button.textContent.trim()} command completed`);
    });
  });
});

elements.sendText.addEventListener("click", submitText);
elements.text.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") void submitText();
});
elements.clearLog.addEventListener("click", () => {
  elements.log.replaceChildren();
});

elements.screenInput.addEventListener("pointerdown", (event) => {
  const point = normalizedPoint(event);
  if (!point) return;
  gesture = {
    pointerId: event.pointerId,
    start: point,
    end: point,
    startedAt: performance.now(),
  };
  elements.screenInput.setPointerCapture(event.pointerId);
});
elements.screenInput.addEventListener("pointermove", (event) => {
  if (!gesture || gesture.pointerId !== event.pointerId) return;
  const point = normalizedPoint(event, true);
  if (point) gesture.end = point;
});
elements.screenInput.addEventListener("pointerup", (event) => {
  void finishGesture(event);
});
elements.screenInput.addEventListener("pointercancel", cancelGesture);
elements.screenInput.addEventListener("contextmenu", (event) => event.preventDefault());

function connect() {
  clearInterval(statusTimer);
  pollStatus();
  statusTimer = setInterval(pollStatus, 1_000);
}

async function pollStatus() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error(`Status ${response.status}`);
    updateStatus(await response.json());
    authorizationReported = false;
    document.querySelector('[data-step="browser"]').dataset.ready = "true";
  } catch (error) {
    document.querySelector('[data-step="browser"]').dataset.ready = "false";
    if (!authorizationReported) {
      addLog(
        error.message === "Status 401"
          ? "Open this dashboard from the Mirror Relay menu or CLI"
          : `Bridge status unavailable: ${error.message}`,
      );
      authorizationReported = true;
    }
  }
}

async function send(value) {
  return post("/api/act", value);
}

async function post(path, value) {
  const response = await fetch(path, {
    method: "POST",
    headers: value ? { "Content-Type": "application/json" } : {},
    body: value ? JSON.stringify(value) : undefined,
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || `Request ${response.status}`);
  return payload;
}

function normalizedPoint(event, clamp = false) {
  const rect = elements.screenInput.getBoundingClientRect();
  const frame = containedFrame(rect, captureSize);
  let x = (event.clientX - frame.left) / frame.width;
  let y = (event.clientY - frame.top) / frame.height;
  if (clamp) {
    x = Math.min(1, Math.max(0, x));
    y = Math.min(1, Math.max(0, y));
  } else if (x < 0 || x > 1 || y < 0 || y > 1) {
    return null;
  }
  return { x, y };
}

async function finishGesture(event) {
  if (!gesture || gesture.pointerId !== event.pointerId) return;
  const finished = gesture;
  const point = normalizedPoint(event, true);
  if (point) finished.end = point;
  cancelGesture(event);

  try {
    await send(
      gestureCommand(
        finished.start,
        finished.end,
        performance.now() - finished.startedAt,
      ),
    );
  } catch (error) {
    addLog(`Control failed: ${error.message}`);
  }
}

function cancelGesture(event) {
  if (!gesture || gesture.pointerId !== event.pointerId) return;
  if (elements.screenInput.hasPointerCapture(event.pointerId)) {
    elements.screenInput.releasePointerCapture(event.pointerId);
  }
  gesture = undefined;
}

async function submitText() {
  const text = elements.text.value;
  if (!text.trim() || elements.sendText.disabled) return;
  await runButtonAction(elements.sendText, async () => {
    await send({ type: "type", text });
    elements.text.value = "";
    addLog(`Sent ${text.length} character${text.length === 1 ? "" : "s"}`);
  });
}

async function runButtonAction(button, action) {
  button.disabled = true;
  try {
    await action();
  } catch (error) {
    addLog(`Bridge error: ${error.message}`);
  } finally {
    button.disabled = false;
  }
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
  elements.latency.textContent =
    live && Number.isFinite(status.frameAgeMs)
      ? `${status.frameAgeMs} ms frame age`
      : "awaiting frames";

  document.querySelector('[data-step="phone"]').dataset.ready = String(live);
  document.querySelector('[data-step="continuity"]').dataset.ready = String(live);
  document.querySelector('[data-step="bridge"]').dataset.ready = String(live);

  if (!live) {
    elements.emptyTitle.textContent = titleForPhase(status.phase);
    elements.emptyCopy.textContent =
      status.message || "Keep the iPhone nearby, powered on, and locked.";
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
    reconnecting: "Reconnecting",
    permission: "Permission",
    error: "Error",
    stopped: "Stopped",
  }[phase] || phase;
}

function titleForPhase(phase) {
  return {
    permission: "Permission required",
    reconnecting: "Reconnecting to iPhone Mirroring",
    error: "Bridge error",
    stopped: "Bridge stopped",
  }[phase] || "Waiting for iPhone Mirroring";
}
