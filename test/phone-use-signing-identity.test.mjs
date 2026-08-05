import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const projectDirectory = fileURLToPath(new URL("..", import.meta.url));
const signingScript = path.join(projectDirectory, "scripts/signing-identity.sh");
const firstHash = "1111111111111111111111111111111111111111";
const secondHash = "2222222222222222222222222222222222222222";

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'"'"'`)}'`;
}

function selectIdentity({
  stateDirectory,
  requested = "",
  identities,
  legacyPinFile = path.join(stateDirectory, "legacy-signing-identity-sha1"),
}) {
  const identityLines = identities
    .map(({ hash, name }) => `${hash}\t${name}`)
    .join("\n");
  const command = `
    source ${shellQuote(signingScript)}
    phone_use_list_signing_identities() {
      print -r -- ${shellQuote(identityLines)}
    }
    phone_use_select_development_identity ${shellQuote(requested)}
  `;
  return spawnSync("zsh", ["-c", command], {
    encoding: "utf8",
    env: {
      ...process.env,
      PROJECT_DIR: projectDirectory,
      PHONE_USE_SIGNING_STATE_DIR: stateDirectory,
      PHONE_USE_SIGNING_PIN_FILE: path.join(
        stateDirectory,
        "signing-identity-sha1",
      ),
      PHONE_USE_LEGACY_SIGNING_PIN_FILE: legacyPinFile,
    },
  });
}

const identities = [
  { hash: firstHash, name: "Apple Development: First" },
  { hash: secondHash, name: "Apple Development: Second" },
];

test("explicit first-run selection creates the stable signing pin", async (t) => {
  const stateDirectory = await mkdtemp(path.join(os.tmpdir(), "phone-use-signing-"));
  t.after(() => rm(stateDirectory, { recursive: true, force: true }));

  const result = selectIdentity({
    stateDirectory,
    requested: secondHash,
    identities,
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), secondHash);
  assert.equal(
    (await readFile(path.join(stateDirectory, "signing-identity-sha1"), "utf8")).trim(),
    secondHash,
  );
});

test("an existing pin resolves ambiguity without another override", async (t) => {
  const stateDirectory = await mkdtemp(path.join(os.tmpdir(), "phone-use-signing-"));
  t.after(() => rm(stateDirectory, { recursive: true, force: true }));
  await writeFile(path.join(stateDirectory, "signing-identity-sha1"), `${firstHash}\n`);

  const result = selectIdentity({ stateDirectory, identities });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), firstHash);
});

test("implicit first run refuses ambiguous development identities", async (t) => {
  const stateDirectory = await mkdtemp(path.join(os.tmpdir(), "phone-use-signing-"));
  t.after(() => rm(stateDirectory, { recursive: true, force: true }));

  const result = selectIdentity({ stateDirectory, identities });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Multiple Apple Development identities/);
});

test("explicit selection cannot silently replace an existing pin", async (t) => {
  const stateDirectory = await mkdtemp(path.join(os.tmpdir(), "phone-use-signing-"));
  t.after(() => rm(stateDirectory, { recursive: true, force: true }));
  const pinPath = path.join(stateDirectory, "signing-identity-sha1");
  await writeFile(pinPath, `${firstHash}\n`);

  const result = selectIdentity({
    stateDirectory,
    requested: secondHash,
    identities,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /does not match the pinned identity/);
  assert.equal((await readFile(pinPath, "utf8")).trim(), firstHash);
});

test("the rebrand migrates the legacy signing pin", async (t) => {
  const stateDirectory = await mkdtemp(path.join(os.tmpdir(), "phone-use-signing-"));
  t.after(() => rm(stateDirectory, { recursive: true, force: true }));
  const legacyPinFile = path.join(stateDirectory, "legacy-signing-identity-sha1");
  await writeFile(legacyPinFile, `${secondHash}\n`);

  const result = selectIdentity({ stateDirectory, identities, legacyPinFile });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), secondHash);
  assert.equal(
    (await readFile(path.join(stateDirectory, "signing-identity-sha1"), "utf8")).trim(),
    secondHash,
  );
});

test("legacy signing migration runs only once", async (t) => {
  const stateDirectory = await mkdtemp(path.join(os.tmpdir(), "phone-use-signing-"));
  t.after(() => rm(stateDirectory, { recursive: true, force: true }));
  const legacyPinFile = path.join(stateDirectory, "legacy-signing-identity-sha1");
  const pinFile = path.join(stateDirectory, "signing-identity-sha1");
  await writeFile(legacyPinFile, `${secondHash}\n`);

  const migrated = selectIdentity({ stateDirectory, identities, legacyPinFile });
  assert.equal(migrated.status, 0, migrated.stderr);
  assert.equal(migrated.stdout.trim(), secondHash);

  await rm(pinFile);
  const rotated = selectIdentity({
    stateDirectory,
    requested: firstHash,
    identities,
    legacyPinFile,
  });

  assert.equal(rotated.status, 0, rotated.stderr);
  assert.equal(rotated.stdout.trim(), firstHash);
  assert.equal((await readFile(pinFile, "utf8")).trim(), firstHash);
});
