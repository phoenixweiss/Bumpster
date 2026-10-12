import { execFileSync } from "node:child_process";

function git(...args) {
  return execFileSync("git", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

try {
  const [tag, expectedCommit, mainBranch] = process.argv.slice(2);
  assert(
    process.argv.length === 5,
    "Usage: validate-release.mjs TAG EXPECTED_COMMIT MAIN_BRANCH",
  );
  assert(
    /^website\/v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag),
    "Expected website/vMAJOR.MINOR.PATCH.",
  );
  git("check-ref-format", "--branch", mainBranch);
  const ref = `refs/tags/${tag}`;
  assert(
    git("cat-file", "-t", ref) === "tag",
    "Website release tag must be annotated.",
  );
  const commit = git("rev-parse", `${ref}^{commit}`);
  assert(
    commit === git("rev-parse", "HEAD"),
    "Website tag must match the checked out commit.",
  );
  assert(
    !expectedCommit || commit === expectedCommit,
    "Website tag must match the workflow commit.",
  );
  const version = tag.slice("website/v".length);
  assert(
    git("show", `${commit}:website/VERSION`) === version,
    "Website tag must match website/VERSION.",
  );
  const manifest = JSON.parse(git("show", `${commit}:website/package.json`));
  assert(
    manifest.version === version,
    "Website manifest must match website/VERSION.",
  );
  const profile = JSON.parse(
    git("show", `${commit}:.bumpster/packages/website.json`),
  );
  assert(
    Object.keys(profile).sort().join(",") ===
      "packageJson,tagPrefix,versionFile" &&
      profile.versionFile === "website/VERSION" &&
      profile.packageJson === "website/package.json" &&
      profile.tagPrefix === "website/v",
    "Website release must use the repository website profile.",
  );
  assert(
    git("show", "-s", "--format=%s", commit) === `bump version to ${version}`,
    "Website tag must point to a version bump commit.",
  );
  git(
    "fetch",
    "--quiet",
    "--no-tags",
    "origin",
    `+refs/heads/${mainBranch}:refs/remotes/origin/${mainBranch}`,
  );
  git(
    "merge-base",
    "--is-ancestor",
    commit,
    `refs/remotes/origin/${mainBranch}`,
  );
  const published = git(
    "ls-remote",
    "--exit-code",
    "--tags",
    "origin",
    ref,
    `${ref}^{}`,
  );
  assert(
    published.split("\n").includes(`${git("rev-parse", ref)}\t${ref}`) &&
      published.split("\n").includes(`${commit}\t${ref}^{}`),
    "Website tag must be published unchanged on origin.",
  );
  console.log(`Validated website release ${tag} at ${commit}.`);
} catch (error) {
  console.error(`Invalid website release: ${error.message}`);
  process.exitCode = 1;
}
