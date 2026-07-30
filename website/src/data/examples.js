export const installCommand =
  '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/phoenixweiss/Bumpster/main/install.sh)"';

export const pathCommand =
  "echo 'export PATH=\"$HOME/.bumpster/bin:$PATH\"' >> ~/.bashrc";

export const uninstallCommand = 'rm -rf -- "$HOME/.bumpster"';

export const bumpOptions = {
  patch: {
    command: "bumpster --patch",
    shortCommand: "bump -p",
    previous: "1.4.2",
    next: "1.4.3",
  },
  minor: {
    command: "bumpster --minor",
    shortCommand: "bump -m",
    previous: "1.4.2",
    next: "1.5.0",
  },
  major: {
    command: "bumpster --major",
    shortCommand: "bump -M",
    previous: "1.4.2",
    next: "2.0.0",
  },
};

export function createTerminalLines(release, releaseType) {
  return [
    {
      id: "current",
      segments: [
        { text: "Current version is " },
        { text: release.previous, variable: true },
      ],
    },
    {
      id: "preflight-start",
      segments: [{ text: "Running release preflight checks." }],
    },
    {
      id: "preflight-complete",
      segments: [{ text: "Release preflight checks passed." }],
    },
    {
      id: "plan",
      segments: [
        { text: "Release plan: " },
        { text: release.previous, variable: true },
        { text: " -> " },
        { text: release.next, variable: true },
        { text: " (" },
        { text: releaseType, variable: true },
        { text: ")." },
      ],
    },
    {
      id: "commit",
      segments: [
        { text: "Created version commit for " },
        { text: release.next, variable: true },
        { text: "." },
      ],
    },
    {
      id: "publish",
      segments: [
        { text: "Publishing 'dev', 'main', and tag '" },
        { text: `v${release.next}`, variable: true },
        { text: "' atomically." },
      ],
    },
    {
      id: "published",
      segments: [{ text: "Release branches and tag published successfully." }],
    },
    {
      id: "return",
      segments: [{ text: "Returning to branch 'dev'." }],
    },
  ];
}

export const configExample = `# ./.bumpsterrc
GIT_MASTER_BRANCH="main"
GIT_DEVELOP_BRANCH="dev"
ENABLE_LOGGING="true"
SYNC_WITH_PACKAGE_JSON="true"
BEFORE_BUMP_BRANCH="dev"
AFTER_BUMP_BRANCH="dev"`;

export const hooksExample = `#!/usr/bin/env bash
# .bumpster/hooks/pre-bump

printf 'Checking %s → %s\\n' \\
  "$BUMPSTER_PREV_VERSION" \\
  "$BUMPSTER_NEW_VERSION"

npm test || exit 1`;

export const featureExample = `bumpster --create-feature

git add .
git commit -m "Add feature"

bumpster --close-feature`;
