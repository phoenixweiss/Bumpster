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
  hotfixExample,
  homebrewInstallCommand,
  homebrewTrustCommand,
  homebrewUninstallCommand,
  homebrewUpdateCommand,
  hooksExample,
  pathCommand,
  standaloneInstallCommand,
  standaloneUninstallCommand,
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
  brandLockup,
  websiteLockup,
  brandFavicon,
  websiteFavicon,
  englishIndex,
  russianIndex,
  manifestSource,
  terminalLogo,
] = await Promise.all([
  readCliHelp(),
  readRepositoryFile("lib/functions.sh"),
  readRepositoryFile("docs/CLI_CONTRACT.md"),
  readRepositoryFile("docs/CLI_CONTRACT_RU.md"),
  readRepositoryFile("README.md"),
  readRepositoryFile("README_RU.md"),
  readRepositoryFile("scripts/build-runtime.sh"),
  readRepositoryFile("docs/brand/bumpster-lockup.svg"),
  readRepositoryFile("website/src/assets/bumpster-lockup.svg"),
  readRepositoryFile("docs/brand/bumpster-favicon.svg"),
  readRepositoryFile("website/public/favicon.svg"),
  readRepositoryFile("website/index.html"),
  readRepositoryFile("website/ru/index.html"),
  readRepositoryFile("website/public/site.webmanifest"),
  readRepositoryFile("lib/BUMPSTER_LOGO.ASCII"),
]);

assert(
  brandLockup === websiteLockup,
  "Website lockup differs from the canonical brand asset.",
);
assert(
  brandFavicon === websiteFavicon,
  "Website favicon differs from the canonical brand asset.",
);

for (const documentation of [readme, readmeRu]) {
  assertIncludes(
    documentation,
    'src="docs/brand/bumpster-lockup.svg"',
    "README is missing the canonical Bumpster lockup",
  );
}

const sharedWebsiteBrandReferences = [
  "/Bumpster/favicon.svg",
  "/Bumpster/favicon-32.png",
  "/Bumpster/favicon-16.png",
  "/Bumpster/apple-touch-icon.png",
  "https://phoenixweiss.github.io/Bumpster/og-image.png",
  'content="1200"',
  'content="630"',
  'content="summary_large_image"',
];

for (const indexSource of [englishIndex, russianIndex]) {
  for (const reference of sharedWebsiteBrandReferences) {
    assertIncludes(
      indexSource,
      reference,
      "Website metadata is missing a brand asset reference",
    );
  }
}

const manifest = JSON.parse(manifestSource);
assert(
  manifest.background_color === "#f3f0ea" && manifest.theme_color === "#941e3d",
  "Web manifest colors differ from the approved brand palette.",
);
assertSameSet(
  new Set(manifest.icons.map(({ src }) => src)),
  new Set([
    "/Bumpster/favicon.svg",
    "/Bumpster/icon-192.png",
    "/Bumpster/icon-512.png",
  ]),
  "Web manifest icon list differs from the branded icon set.",
);

const terminalLogoLines = terminalLogo.trimEnd().split("\n");
assert(
  terminalLogoLines.length === 3 &&
    Math.max(...terminalLogoLines.map((line) => line.length)) === 27,
  "Terminal logo must remain within its 27-column, three-line contract.",
);
assert(
  /^[\x20-\x7e\n]+$/.test(terminalLogo),
  "Terminal logo must contain only printable 7-bit ASCII.",
);
assertIncludes(
  terminalLogo,
  "| X |.| Y |.| Z |  BUMPSTER",
  "Terminal logo must use uppercase semantic-version symbols",
);

const brandRasterDimensions = new Map([
  ["docs/brand/bumpster-favicon.png", [512, 512]],
  ["docs/brand/bumpster-favicon-sheet.png", [1600, 1000]],
  ["docs/brand/bumpster-flat-terminal-sheet.png", [1800, 1200]],
  ["docs/brand/bumpster-lockup.png", [1480, 280]],
  ["docs/brand/bumpster-mark.png", [1200, 560]],
  ["docs/brand/bumpster-social-card.png", [1200, 630]],
  ["website/public/apple-touch-icon.png", [180, 180]],
  ["website/public/favicon-16.png", [16, 16]],
  ["website/public/favicon-32.png", [32, 32]],
  ["website/public/icon-192.png", [192, 192]],
  ["website/public/icon-512.png", [512, 512]],
  ["website/public/og-image.png", [1200, 630]],
]);

for (const [path, [expectedWidth, expectedHeight]] of brandRasterDimensions) {
  const image = await readFile(join(repositoryRoot, path));
  assert(
    image.length > 8 && image.subarray(1, 4).toString("ascii") === "PNG",
    `Brand raster is missing or is not a PNG: ${path}`,
  );
  assert(
    image.readUInt32BE(16) === expectedWidth &&
      image.readUInt32BE(20) === expectedHeight,
    `Brand raster has unexpected dimensions: ${path}`,
  );
}

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
  hotfix: ["-H", "--hotfix"],
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
    homebrewInstallCommand,
    "Homebrew installation command differs from README",
  );
  assertIncludes(
    documentation,
    homebrewUpdateCommand,
    "Homebrew update command differs from README",
  );
  assertIncludes(
    documentation,
    homebrewTrustCommand,
    "Homebrew trust command differs from README",
  );
  assertIncludes(
    documentation,
    homebrewUninstallCommand,
    "Homebrew uninstall command differs from README",
  );
  assertIncludes(
    documentation,
    standaloneInstallCommand,
    "Standalone installation command differs from README",
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

for (const locale of [content.en, content.ru]) {
  assertIncludes(
    locale.start.homebrewNote,
    homebrewTrustCommand,
    "Homebrew trust command is missing from website guidance",
  );
}

assert(
  standaloneUninstallCommand === 'rm -rf -- "$HOME/.bumpster"',
  "Website standalone uninstall command changed unexpectedly.",
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
  "BUMPSTER_RELEASE_TYPE",
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
  "BUMPSTER_RELEASE_TYPE",
]) {
  assertIncludes(
    cliSource,
    implementationValue,
    "Hook example differs from implementation",
  );
}

for (const branchCommand of [
  "bumpster --create-feature",
  "bumpster --close-feature",
]) {
  assertIncludes(featureExample, branchCommand, "Branch example is incomplete");
  assertIncludes(
    cliHelp,
    branchCommand.replace("bumpster ", ""),
    "Branch example differs from CLI help",
  );
}

for (const hotfixCommand of ["bumpster --create-hotfix", "bumpster --hotfix"]) {
  assertIncludes(hotfixExample, hotfixCommand, "Hotfix example is incomplete");
  assertIncludes(
    cliHelp,
    hotfixCommand.replace("bumpster ", ""),
    "Hotfix example differs from CLI help",
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

const hotfixTerminalText = createTerminalLines(bumpOptions.hotfix, "hotfix")
  .map((line) => line.segments.map((segment) => segment.text).join(""))
  .join("\n");

for (const message of [
  "Release plan: 1.4.2 -> 1.4.3 (hotfix).",
  "Created version commit for 1.4.3.",
  "Publishing 'dev', 'main', and tag 'v1.4.3' atomically.",
]) {
  assertIncludes(
    hotfixTerminalText,
    message,
    "Hotfix terminal example is incomplete",
  );
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
