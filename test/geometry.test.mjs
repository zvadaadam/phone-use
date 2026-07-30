import test from "node:test";
import assert from "node:assert/strict";
import { containedFrame } from "../public/geometry.js";

test("containedFrame removes vertical letterboxing", () => {
  assert.deepEqual(
    containedFrame(
      { left: 10, top: 20, width: 200, height: 500 },
      { width: 100, height: 200 },
    ),
    { left: 10, top: 70, width: 200, height: 400 },
  );
});

test("containedFrame removes horizontal letterboxing", () => {
  assert.deepEqual(
    containedFrame(
      { left: 10, top: 20, width: 500, height: 200 },
      { width: 200, height: 100 },
    ),
    { left: 60, top: 20, width: 400, height: 200 },
  );
});
