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
  restart: document.querySelector("#restart-button"),
  close: document.querySelector("#close-session"),
  log: document.querySelector("#event-log"),
  clearLog: document.querySelector("#clear-log"),
  latency: document.querySelector("#latency-label"),
};

let statusTimer;
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

elements.clearLog.addEventListener("click", () => {
  elements.log.replaceChildren();
});

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
          ? "Open this dashboard from the Phone Use menu or CLI"
          : `Bridge status unavailable: ${error.message}`,
      );
      authorizationReported = true;
    }
  }
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
  elements.body.dataset.live = String(live);
  elements.statusPill.dataset.status = status.phase;
  elements.statusLabel.textContent = friendlyPhase(status.phase);
  elements.fps.textContent = `${status.fps || 0} fps`;
  elements.size.textContent = status.width && status.height
    ? `${status.width}×${status.height}`
    : "—";
  const captureMode = {
    screenCaptureKit: "ScreenCaptureKit",
    screenshotFallback: "Screenshot fallback",
  }[status.captureMode];
  elements.bridgeDetail.textContent = [status.message || "Waiting", captureMode]
    .filter(Boolean)
    .join(" · ");
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
