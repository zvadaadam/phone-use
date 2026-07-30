const SHORTCUTS = new Set(["home", "appSwitcher", "spotlight"]);
const POINTER_PHASES = new Set(["down", "move", "up"]);
const MAX_TEXT_LENGTH = 4_096;

export function validateControl(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Control message must be an object");
  }

  if (value.type === "pointer") {
    const { phase, x, y } = value;
    if (!POINTER_PHASES.has(phase)) {
      throw new Error("Pointer phase must be down, move, or up");
    }
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
      throw new Error("Pointer coordinates must be numbers between 0 and 1");
    }
    return { type: "pointer", phase, x, y };
  }

  if (value.type === "type") {
    if (typeof value.text !== "string" || !value.text.length) {
      throw new Error("Text must be a non-empty string");
    }
    return { type: "type", text: value.text.slice(0, MAX_TEXT_LENGTH) };
  }

  if (value.type === "shortcut") {
    if (!SHORTCUTS.has(value.name)) {
      throw new Error("Unknown shortcut");
    }
    return { type: "shortcut", name: value.name };
  }

  if (value.type === "restart") {
    return { type: "restart" };
  }

  throw new Error("Unknown control message type");
}
