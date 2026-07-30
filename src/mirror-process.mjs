import { EventEmitter } from "node:events";
import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { WireDecoder } from "./protocol.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_HELPER = join(ROOT, "native", ".build", "release", "mirror-bridge");

export class MirrorProcess extends EventEmitter {
  #child;
  #decoder;
  #frameCount = 0;
  #fpsTimer;

  latestFrame = null;
  status = {
    phase: "stopped",
    message: "Bridge has not started",
    fps: 0,
    width: null,
    height: null,
  };

  constructor({ helperPath = DEFAULT_HELPER } = {}) {
    super();
    this.helperPath = helperPath;
    this.#fpsTimer = setInterval(() => {
      this.status = { ...this.status, fps: this.#frameCount };
      this.#frameCount = 0;
      this.emit("status", this.status);
    }, 1_000);
    this.#fpsTimer.unref();
  }

  start() {
    if (this.#child) return;
    if (!existsSync(this.helperPath)) {
      this.#setStatus({
        phase: "missing",
        message: "Native helper is not built. Run npm run build:native.",
      });
      return;
    }

    this.#setStatus({ phase: "starting", message: "Starting native bridge" });
    this.#decoder = new WireDecoder();
    this.#decoder.on("frame", (frame) => {
      this.latestFrame = frame;
      this.#frameCount += 1;
      this.emit("frame", frame);
    });
    this.#decoder.on("status", (status) => this.#setStatus(status));
    this.#decoder.on("error", (error) => {
      this.#setStatus({ phase: "error", message: error.message });
    });

    this.#child = spawn(this.helperPath, [], {
      cwd: ROOT,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.#child.stdout.on("data", (chunk) => this.#decoder.push(chunk));
    this.#child.stderr.setEncoding("utf8");
    this.#child.stderr.on("data", (message) => {
      for (const line of message.trim().split("\n")) {
        if (line) this.emit("log", line);
      }
    });
    this.#child.on("error", (error) => {
      this.#setStatus({ phase: "error", message: error.message });
    });
    this.#child.on("exit", (code, signal) => {
      this.#child = undefined;
      this.#setStatus({
        phase: "stopped",
        message: `Native bridge stopped (${signal || code || "unknown"})`,
      });
    });
  }

  send(control) {
    if (!this.#child?.stdin.writable) {
      throw new Error("Native bridge is not running");
    }
    this.#child.stdin.write(`${JSON.stringify(control)}\n`);
  }

  restart() {
    if (!this.#child) {
      this.start();
      return;
    }
    const child = this.#child;
    child.once("exit", () => this.start());
    child.kill("SIGTERM");
  }

  stop() {
    clearInterval(this.#fpsTimer);
    this.#child?.kill("SIGTERM");
    this.#child = undefined;
  }

  #setStatus(update) {
    this.status = { ...this.status, ...update };
    this.emit("status", this.status);
  }
}
