import test from "node:test";
import assert from "node:assert/strict";
import { validateControl } from "../src/control.mjs";

test("validateControl accepts normalized pointer events", () => {
  assert.deepEqual(
    validateControl({ type: "pointer", phase: "move", x: 0.25, y: 1 }),
    { type: "pointer", phase: "move", x: 0.25, y: 1 },
  );
});

test("validateControl rejects pointer coordinates outside the surface", () => {
  assert.throws(
    () => validateControl({ type: "pointer", phase: "down", x: -0.1, y: 0.4 }),
    /between 0 and 1/,
  );
});

test("validateControl only allows known shortcuts", () => {
  assert.deepEqual(
    validateControl({ type: "shortcut", name: "home" }),
    { type: "shortcut", name: "home" },
  );
  assert.throws(
    () => validateControl({ type: "shortcut", name: "purchase" }),
    /Unknown shortcut/,
  );
});

test("validateControl bounds typed text", () => {
  const text = "x".repeat(5_000);
  assert.equal(validateControl({ type: "type", text }).text.length, 4_096);
});
