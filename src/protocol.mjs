import { EventEmitter } from "node:events";

const HEADER_BYTES = 5;
const MAX_MESSAGE_BYTES = 32 * 1024 * 1024;

export const WireTag = Object.freeze({
  frame: 1,
  status: 2,
});

export class WireDecoder extends EventEmitter {
  #buffer = Buffer.alloc(0);

  push(chunk) {
    if (!chunk?.length) return;
    this.#buffer = this.#buffer.length
      ? Buffer.concat([this.#buffer, chunk])
      : Buffer.from(chunk);

    while (this.#buffer.length >= HEADER_BYTES) {
      const tag = this.#buffer[0];
      const length = this.#buffer.readUInt32BE(1);
      if (length > MAX_MESSAGE_BYTES) {
        this.#buffer = Buffer.alloc(0);
        this.emit("error", new Error(`Native message too large: ${length} bytes`));
        return;
      }
      if (this.#buffer.length < HEADER_BYTES + length) return;

      const payload = this.#buffer.subarray(HEADER_BYTES, HEADER_BYTES + length);
      this.#buffer = this.#buffer.subarray(HEADER_BYTES + length);

      if (tag === WireTag.frame) {
        this.emit("frame", Buffer.from(payload));
      } else if (tag === WireTag.status) {
        try {
          this.emit("status", JSON.parse(payload.toString("utf8")));
        } catch (error) {
          this.emit("error", new Error(`Invalid native status JSON: ${error.message}`));
        }
      } else {
        this.emit("error", new Error(`Unknown native message tag: ${tag}`));
      }
    }
  }
}

export function encodeWireMessage(tag, payload) {
  const body = Buffer.isBuffer(payload) ? payload : Buffer.from(payload);
  const header = Buffer.alloc(HEADER_BYTES);
  header[0] = tag;
  header.writeUInt32BE(body.length, 1);
  return Buffer.concat([header, body]);
}
