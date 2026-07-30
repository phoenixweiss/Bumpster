import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { content } from "../src/data/content.js";
import {
  bumpOptions,
  configExample,
  createTerminalLines,
  featureExample,
  hooksExample,
  installCommand,
  pathCommand,
  uninstallCommand,
} from "../src/data/examples.js";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(scriptDirectory, "..");
const repositoryRoot = resolve(websiteRoot, "..");

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function assertIncludes(value, expected, message) {
  assert(value.includes(expected), `${message}: ${expected}`);
}

function assertSameSet(actual, expected, message) {
  const actualValues = [...actual].sort();
  const expectedValues = [...expected].sort();

  assert(
    JSON.stringify(actualValues) === JSON.stringify(expectedValues),
    `${message}\nExpected: ${expectedValues.join(", ")}\nActual: ${actualValues.join(", ")}`,
  );
}

async function readRepositoryFile(path) {
  return readFile(join(repositoryRoot, path), "utf8");
}

async function readCliHelp() {
  const isolatedHome = await mkdtemp(join(tmpdir(), "bumpster-site-content."));

  try {
    const result = spawnSync(
      "bash",
      [join(repositoryRoot, "bumpster.sh"), "--help"],
      {
        cwd: repositoryRoot,
        encoding: "utf8",
        env: {
          ...process.env,
          BUMPSTER_HOME: join(isolatedHome, ".bumpster"),
          HOME: isolatedHome,
        },
      },
    );

    if (result.status !== 0) {
      fail(`Could not read CLI help:\n${result.stderr || result.stdout}`);
    }

    return result.stdout;
  } finally {
    await rm(isolatedHome, { force: true, recursive: true });
  }
}

const [
  cliHelp,
  cliSource,
  contract,
  contractRu,
  readme,
  readmeRu,
  runtimeBuilder,
] = await Promise.all([
  readCliHelp(),
  readRepositoryFile("lib/functions.sh"),
  readRepositoryFile("docs/CLI_CONTRACT.md"),
  readRepositoryFile("docs/CLI_CONTRACT_RU.md"),
  readRepositoryFile("README.md"),
  readRepositoryFile("README_RU.md"),
  readRepositoryFile("scripts/build-runtime.sh"),
]);

const englishCommands = content.en.commands.items.map(([short, long]) => [
  short,
  long,
]);
const russianCommands = content.ru.commands.items.map(([short, long]) => [
  short,
  long,
]);

assert(
  JSON.stringify(englishCommands) === JSON.stringify(russianCommands),
  "English and Russian command lists differ.",
);

for (const [shortOption, longOption] of englishCommands) {
  assertIncludes(
    cliHelp,
    `${shortOption}, ${longOption}`,
    "Website command is missing from CLI help",
  );
  assertIncludes(
    contract,
    `\`${shortOption}\`, \`${longOption}\``,
    "Website command is missing from the CLI contract",
  );
}

const expectedReleaseOptions = {
  major: ["-M", "--major"],
  minor: ["-m", "--minor"],
  patch: ["-p", "--patch"],
};

for (const [releaseType, [shortOption, longOption]] of Object.entries(
  expectedReleaseOptions,
)) {
  const release = bumpOptions[releaseType];

  assert(
    release.command === `bumpster ${longOption}`,
    `Canonical ${releaseType} command differs from CLI options.`,
  );
  assert(
    release.shortCommand === `bump ${shortOption}`,
    `Short ${releaseType} command differs from CLI options.`,
  );
}

for (const documentation of [readme, readmeRu]) {
  assertIncludes(
    documentation,
    installCommand,
    "Installation command differs from README",
  );
  assertIncludes(
    documentation,
    pathCommand,
    "PATH command differs from README",
  );
  assertIncludes(
    documentation,
    "~/.bumpster",
    "Installation directory is missing from README",
  );
}

assert(
  uninstallCommand === 'rm -rf -- "$HOME/.bumpster"',
  "Website uninstall command changed unexpectedly.",
);

const configurationKeys = configExample
  .split("\n")
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.slice(0, line.indexOf("=")));

for (const key of configurationKeys) {
  assertIncludes(
    cliHelp,
    key,
    "Configuration example key is missing from CLI help",
  );
  assertIncludes(
    contract,
    `\`${key}\``,
    "Configuration key is missing from contract",
  );
  assertIncludes(
    contractRu,
    `\`${key}\``,
    "Configuration key is missing from Russian contract",
  );
  assertIncludes(readme, key, "Configuration key is missing from README");
  assertIncludes(
    readmeRu,
    key,
    "Configuration key is missing from Russian README",
  );
}

for (const hookValue of [
  ".bumpster/hooks/pre-bump",
  "BUMPSTER_PREV_VERSION",
  "BUMPSTER_NEW_VERSION",
]) {
  assertIncludes(hooksExample, hookValue, "Hook example is incomplete");
  assertIncludes(contract, hookValue, "Hook example differs from CLI contract");
}

for (const implementationValue of [
  'project_hook_path="$(pwd)/.bumpster/hooks/$hook_name"',
  'run_hook "pre-bump"',
  'run_hook "post-bump"',
  "BUMPSTER_PREV_VERSION",
  "BUMPSTER_NEW_VERSION",
]) {
  assertIncludes(
    cliSource,
    implementationValue,
    "Hook example differs from implementation",
  );
}

for (const featureCommand of [
  "bumpster --create-feature",
  "bumpster --close-feature",
]) {
  assertIncludes(
    featureExample,
    featureCommand,
    "Feature example is incomplete",
  );
  assertIncludes(
    cliHelp,
    featureCommand.replace("bumpster ", ""),
    "Feature example differs from CLI help",
  );
}

const terminalText = createTerminalLines(bumpOptions.patch, "patch")
  .map((line) => line.segments.map((segment) => segment.text).join(""))
  .join("\n");

for (const message of [
  "Current version is 1.4.2",
  "Running release preflight checks.",
  "Release preflight checks passed.",
  "Release plan: 1.4.2 -> 1.4.3 (patch).",
  "Created version commit for 1.4.3.",
  "Publishing 'dev', 'main', and tag 'v1.4.3' atomically.",
  "Release branches and tag published successfully.",
  "Returning to branch 'dev'.",
]) {
  assertIncludes(terminalText, message, "Terminal example is incomplete");
}

for (const sourceMessage of [
  '"Current version is $release_current_version"',
  'log "Running release preflight checks."',
  'log "Release preflight checks passed."',
  '"Release plan: $release_current_version -> $release_new_version ($release_version_type)."',
  '"Created version commit for $release_new_version."',
  "\"Publishing '$release_develop_branch', '$release_master_branch', and tag 'v$release_new_version' atomically.\"",
  'log "Release branches and tag published successfully."',
  "log \"Returning to branch '$release_after_branch'.\"",
]) {
  assertIncludes(
    cliSource,
    sourceMessage,
    "Terminal example differs from CLI implementation",
  );
}

const runtimeArray = runtimeBuilder.match(/runtime_files=\(\n([\s\S]*?)\n\)/);
assert(runtimeArray, "Could not read the runtime file whitelist.");

const runtimeFiles = [...runtimeArray[1].matchAll(/"([^"]+)"/g)].map(
  (match) => match[1],
);
const installedRuntimeSurface = new Set([
  "bin/",
  ...runtimeFiles.map((path) => (path.startsWith("lib/") ? "lib/" : path)),
]);

for (const locale of ["en", "ru"]) {
  const websiteRuntimeSurface = new Set(
    content[locale].footprint.runtimeFiles.map(([path]) => path),
  );

  assertSameSet(
    websiteRuntimeSurface,
    installedRuntimeSurface,
    `${locale.toUpperCase()} runtime list differs from the release whitelist.`,
  );
}

for (const forbiddenPath of ["docs/", "tests/", "website/", ".github/"]) {
  assert(
    !runtimeFiles.some((path) => path.startsWith(forbiddenPath)),
    `Runtime whitelist contains forbidden path: ${forbiddenPath}`,
  );
}

console.log(
  "Website content matches the CLI, documentation, and runtime surface.",
);
