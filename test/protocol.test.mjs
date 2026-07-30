import test from "node:test";
import assert from "node:assert/strict";
import { WireDecoder, WireTag, encodeWireMessage } from "../src/protocol.mjs";

test("WireDecoder handles fragmented native messages", () => {
  const decoder = new WireDecoder();
  const frames = [];
  const statuses = [];
  decoder.on("frame", (frame) => frames.push(frame));
  decoder.on("status", (status) => statuses.push(status));

  const frame = encodeWireMessage(WireTag.frame, Buffer.from([1, 2, 3, 4]));
  const status = encodeWireMessage(
    WireTag.status,
    JSON.stringify({ phase: "streaming", width: 390 }),
  );
  const packet = Buffer.concat([frame, status]);

  decoder.push(packet.subarray(0, 2));
  decoder.push(packet.subarray(2, 9));
  decoder.push(packet.subarray(9));

  assert.deepEqual(frames, [Buffer.from([1, 2, 3, 4])]);
  assert.deepEqual(statuses, [{ phase: "streaming", width: 390 }]);
});

test("WireDecoder reports unknown tags", () => {
  const decoder = new WireDecoder();
  const errors = [];
  decoder.on("error", (error) => errors.push(error.message));
  decoder.push(encodeWireMessage(99, "nope"));
  assert.deepEqual(errors, ["Unknown native message tag: 99"]);
});
