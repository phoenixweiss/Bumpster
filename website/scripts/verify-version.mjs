import { readFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(scriptDirectory, "..");
const repositoryRoot = resolve(websiteRoot, "..");
const distRoot = join(websiteRoot, "dist");
const assetPrefix = "/Bumpster/";

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

const version = (
  await readFile(join(repositoryRoot, "VERSION"), "utf8")
).trim();

assert(
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version),
  "Root VERSION must contain MAJOR.MINOR.PATCH.",
);

async function verifyLocale(label, htmlFile) {
  const html = await readFile(join(distRoot, htmlFile), "utf8");
  const scriptSources = [
    ...html.matchAll(/<script\b[^>]*\bsrc="([^"]+\.js)"/g),
  ].map(([, source]) => source);

  assert(
    scriptSources.length > 0,
    `${label} output does not load a JavaScript bundle.`,
  );

  for (const source of scriptSources) {
    if (!source.startsWith(assetPrefix)) continue;

    const assetPath = resolve(distRoot, source.slice(assetPrefix.length));
    const relativeAssetPath = relative(distRoot, assetPath);

    assert(
      relativeAssetPath &&
        !relativeAssetPath.startsWith("..") &&
        !isAbsolute(relativeAssetPath),
      `${label} output references an invalid script path: ${source}`,
    );

    const bundle = await readFile(assetPath, "utf8");

    if (bundle.includes("Bumpster v") && bundle.includes(version)) return;
  }

  fail(`${label} output does not include Bumpster v${version}.`);
}

await Promise.all([
  verifyLocale("English", "index.html"),
  verifyLocale("Russian", "ru/index.html"),
]);

console.log(`Website output includes Bumpster v${version} in both locales.`);
