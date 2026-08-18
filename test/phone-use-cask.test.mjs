import assert from "node:assert/strict";
import {
  access,
  mkdtemp,
  readFile,
  realpath,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const projectDirectory = fileURLToPath(new URL("..", import.meta.url));
const renderCask = path.join(projectDirectory, "scripts/render-cask.sh");
const packageRelease = path.join(projectDirectory, "scripts/package-release.sh");
const packageMetadata = JSON.parse(
  await readFile(path.join(projectDirectory, "package.json"), "utf8"),
);
const version = packageMetadata.version;

test("the release artifact renders a checksum-pinned local Cask", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "phone use cask-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diskImage = path.join(directory, `Phone-Use-${version}.dmg`);
  const output = path.join(directory, "Casks", "phone-use.rb");
  await writeFile(diskImage, "deterministic test artifact\n");

  const result = spawnSync("zsh", [renderCask, diskImage, output], {
    encoding: "utf8",
    env: {
      ...process.env,
      PHONE_USE_CASK_LOCAL: "1",
    },
  });

  assert.equal(result.status, 0, result.stderr);
  const cask = await readFile(output, "utf8");
  assert.match(cask, /^# typed: strict\n# frozen_string_literal: true\n/);
  assert.match(cask, /cask "phone-use" do/);
  assert.ok(cask.includes(`version "${version}"`));
  assert.match(cask, /sha256 "[a-f0-9]{64}"/);
  const url = cask.match(/url "([^"]+)"/)?.[1];
  assert.ok(url);
  assert.equal(await realpath(fileURLToPath(url)), await realpath(diskImage));
  assert.equal(new URL(url).protocol, "file:");
  assert.match(cask, /phone%20use%20cask-/);
  assert.match(cask, /app "Phone Use\.app"/);
  assert.match(cask, /Contents\/Helpers\/phone-use/);
  assert.match(cask, /depends_on macos: :sequoia/);
  assert.match(cask, /uninstall quit: "com\.adamzvada\.phoneuse"/);
  assert.equal((await stat(output)).mode & 0o777, 0o644);
});

test("the public Cask downloads from the binary tap instead of private source", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "phone-use-cask-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diskImage = path.join(directory, `Phone-Use-${version}.dmg`);
  const output = path.join(directory, "phone-use.rb");
  await writeFile(diskImage, "deterministic test artifact\n");

  const result = spawnSync("zsh", [renderCask, diskImage, output], {
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  const cask = await readFile(output, "utf8");
  assert.ok(
    cask.includes(
      `url "https://github.com/zvadaadam/homebrew-tap/releases/download/phone-use-v${version}/Phone-Use-${version}.dmg"`,
    ),
  );
  assert.doesNotMatch(cask, /zvadaadam\/phone-use\/releases/);
});

test("Cask generation rejects an artifact that cannot match the release", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "phone-use-cask-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diskImage = path.join(directory, "wrong-name.dmg");
  await writeFile(diskImage, "not a release\n");

  const result = spawnSync("zsh", [renderCask, diskImage], {
    encoding: "utf8",
  });

  assert.notEqual(result.status, 0);
  assert.ok(result.stderr.includes(`expected Phone-Use-${version}.dmg`));
});

test("Cask generation rejects an unsafe release URL", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "phone-use-cask-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diskImage = path.join(directory, `Phone-Use-${version}.dmg`);
  await writeFile(diskImage, "not a release\n");

  const result = spawnSync("zsh", [renderCask, diskImage], {
    encoding: "utf8",
    env: {
      ...process.env,
      PHONE_USE_CASK_URL: 'https://example.com/unsafe"url.dmg',
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unsafe characters/);
});

test("Cask generation rejects Ruby interpolation in the URL", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "phone-use-cask-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diskImage = path.join(directory, `Phone-Use-${version}.dmg`);
  const proof = path.join(directory, "proof");
  await writeFile(diskImage, "not a release\n");

  const result = spawnSync("zsh", [renderCask, diskImage], {
    encoding: "utf8",
    env: {
      ...process.env,
      PHONE_USE_CASK_URL: `https://example.com/#{%x(touch ${proof})}`,
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unsafe characters/);
  await assert.rejects(access(proof));
});

test("Cask generation rejects a single backslash in the URL", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "phone-use-cask-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diskImage = path.join(directory, "Phone-Use-" + version + ".dmg");
  await writeFile(diskImage, "not a release\n");

  const result = spawnSync("zsh", [renderCask, diskImage], {
    encoding: "utf8",
    env: {
      ...process.env,
      PHONE_USE_CASK_URL: "https://example.com/unsafe\\path.dmg",
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unsafe characters/);
});

test("release packaging renders the Cask before publishing artifacts", async () => {
  const script = await readFile(packageRelease, "utf8");
  const renderIndex = script.indexOf('"${SCRIPT_DIR}/render-cask.sh"');
  const legacyCleanupIndex = script.indexOf(
    'rm -f "${LEGACY_DMG}" "${LEGACY_SHA256_FILE}"',
  );
  const publishIndex = script.indexOf('mv -f "${WORK_DMG}" "${DMG}"');

  assert.notEqual(renderIndex, -1);
  assert.notEqual(legacyCleanupIndex, -1);
  assert.notEqual(publishIndex, -1);
  assert.ok(renderIndex < publishIndex);
  assert.ok(renderIndex < legacyCleanupIndex);
  assert.ok(legacyCleanupIndex < publishIndex);
  assert.match(
    script,
    /PHONE_USE_CASK_LOCAL=0 \\\nPHONE_USE_CASK_URL= \\\n\s+"\$\{SCRIPT_DIR\}\/render-cask\.sh"/,
  );
});
