const elements = {
  body: document.body,
  statusPill: document.querySelector("#status-pill"),
  statusLabel: document.querySelector("#status-label"),
  deviceTitle: document.querySelector("#device-title"),
  frameLabel: document.querySelector("#frame-label"),
  emptyTitle: document.querySelector("#empty-title"),
  emptyCopy: document.querySelector("#empty-copy"),
  proof: document.querySelector("#proof-label"),
  ios: document.querySelector("#ios-label"),
  hub: document.querySelector("#hub-label"),
  transport: document.querySelector("#transport-value"),
  connection: document.querySelector("#connection-value"),
  developerMode: document.querySelector("#developer-mode-value"),
  internet: document.querySelector("#internet-value"),
  focus: document.querySelector("#focus-value"),
  connect: document.querySelector("#connect-button"),
  refresh: document.querySelector("#refresh-button"),
  clearLog: document.querySelector("#clear-log"),
  log: document.querySelector("#event-log"),
};

let statusTimer;

elements.connect.addEventListener("click", () =>
  runButton(elements.connect, async () => {
    await post("/api/device/connect");
    addLog("Device Hub connection requested");
  }),
);
elements.refresh.addEventListener("click", () =>
  runButton(elements.refresh, pollStatus),
);
elements.clearLog.addEventListener("click", () => elements.log.replaceChildren());

pollStatus();
statusTimer = setInterval(pollStatus, 1_000);
window.addEventListener("pagehide", () => clearInterval(statusTimer));

async function pollStatus() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error("Status " + response.status);
    render(await response.json());
  } catch (error) {
    elements.body.dataset.live = "false";
    elements.statusPill.dataset.status = "unavailable";
    elements.statusLabel.textContent = "API unavailable";
    addLog(
      error.message === "Status 401"
        ? "Open this dashboard from the Phone Use menu or CLI"
        : "Agent API unavailable: " + error.message,
    );
  }
}

async function post(path) {
  const response = await fetch(path, { method: "POST" });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Request " + response.status);
  return payload;
}

async function runButton(button, action) {
  button.disabled = true;
  try {
    await action();
  } catch (error) {
    addLog(error.message);
  } finally {
    button.disabled = false;
    await pollStatus();
  }
}

function render(status) {
  const connected = status.phase === "streaming";
  elements.body.dataset.live = String(connected);
  elements.statusPill.dataset.status = status.phase;
  elements.statusLabel.textContent = phaseLabel(status.phase);
  elements.deviceTitle.textContent = connected ? "Live device" : "Awaiting backend";
  elements.frameLabel.textContent = status.frame
    ? status.frame.width + "×" + status.frame.height + " · " + status.frame.fps + " fps"
    : "no frame";
  elements.proof.textContent = status.proof;
  elements.ios.textContent = "iOS " + status.requirements.minimumIOSVersion + "+";
  elements.hub.textContent = status.message;
  elements.transport.textContent = status.transport;
  elements.connection.textContent = status.requirements.hostConnection;
  elements.developerMode.textContent = status.requirements.developerModeRequired
    ? "required"
    : "not required";
  elements.internet.textContent = status.internetRelayAvailable ? "available" : "not built";
  elements.focus.textContent = status.macFocusPolicy;
  elements.emptyTitle.textContent =
    status.proof === "validated" ? "Waiting for an iPhone" : "Physical proof required";
  elements.emptyCopy.textContent = status.message;
  elements.connect.disabled = status.proof !== "validated";
  renderLogs(status.logs || []);
}

function renderLogs(logs) {
  elements.log.replaceChildren();
  if (!logs.length) {
    addLog("No events yet");
    return;
  }
  for (const entry of logs.slice().reverse()) addLog(entry);
}

function addLog(message) {
  const row = document.createElement("p");
  const time = document.createElement("time");
  const copy = document.createElement("span");
  time.textContent = new Date().toLocaleTimeString([], { hour12: false });
  copy.textContent = message;
  row.append(time, copy);
  elements.log.prepend(row);
  while (elements.log.children.length > 20) elements.log.lastElementChild.remove();
}

function phaseLabel(phase) {
  return {
    unavailable: "Unavailable",
    waitingForDevice: "Waiting for iPhone",
    connecting: "Connecting",
    streaming: "Connected",
    stopped: "Stopped",
  }[phase] || phase;
}
