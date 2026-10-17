# Bumpster CLI compatibility contract

[Русская версия](CLI_CONTRACT_RU.md)

This document describes the CLI behavior you can rely on in Bumpster `1.x`:
commands and short options, configuration, hooks, and the main safety
guarantees. If any of these change incompatibly, the change will be called out
in the changelog.

## Invocation model

`bumpster` is the canonical command. An installation may also provide the
optional `bump` wrapper when that name is available; both wrappers accept the
same arguments.

One invocation accepts zero or one action option. Multiple action options,
including two release types, are rejected before repository or installation
state is changed. Unknown options are also rejected.

Running `bumpster` without an action starts the interactive release flow. It
asks for `major`, `minor`, or `patch`; an empty response selects `patch`.

| Action | Repository required | Primary effect |
| --- | --- | --- |
| `-h`, `--help` | No | Prints help and exits. |
| `-v`, `--version` | No | Prints `Bumpster version: MAJOR.MINOR.PATCH`. |
| `-u`, `--update` | No | Updates a standalone installation from the latest stable GitHub Release. Package-manager installations direct updates back to their package manager. |
| `-s`, `--status` | Yes | Reads branch, working-tree, and upstream status without changing repository state. |
| `-l`, `--create-local-config` | No | Interactively writes `./.bumpsterrc`. |
| `-f`, `--create-feature` | Yes | Creates and checks out a local feature branch from the configured development branch. |
| `-c`, `--close-feature` | Yes | Merges the current feature branch into development, pushes development, and optionally deletes the feature branch. |
| `-x`, `--create-hotfix` | Yes | Fetches the configured release branch and creates a local `hotfix/*` branch from it. |
| `-M`, `--major` | Yes | Runs a major release. |
| `-m`, `--minor` | Yes | Runs a minor release. |
| `-p`, `--patch` | Yes | Runs a patch release. |
| `-H`, `--hotfix` | Yes | Runs a patch release from a dedicated `hotfix/*` branch based on the release branch. |

Help, version, update, and local configuration creation do not require a Git
repository. Status, branch operations, and releases do.

## Hotfix branch creation

`-x` and `--create-hotfix` require a clean worktree and prompt for a short
name. Bumpster fetches `origin`, safely fast-forwards the configured local
release branch, and creates `hotfix/<name>` from that exact commit. If the
release branch does not exist locally, it is created as a tracking branch from
`origin`. An unpublished or divergent local release branch is never reset or
overwritten; the command stops and leaves it unchanged.

## Release guarantees

Every release requires:

- a clean working tree;
- a valid `MAJOR.MINOR.PATCH` value in `VERSION`;
- distinct configured development and release branches;
- correct `origin` upstreams for existing release branches;
- reachable and current remote refs;
- no local or remote tag for the target version.

A major, minor, or patch release also requires the configured
`BEFORE_BUMP_BRANCH` to be checked out locally. A hotfix is always selected
explicitly with `-H` or `--hotfix`; it is not part of the interactive prompt and
ignores `BEFORE_BUMP_BRANCH`. It additionally requires:

- an active non-empty `hotfix/*` branch containing the current release branch;
- local development and release branches exactly matching their `origin` refs;
- no unpublished development commits in the hotfix branch;
- the same starting `VERSION` in the hotfix, development, and release branches.

The release plan and package synchronization input are validated before the
pre-bump hook and before the first release mutation. A successful release:

1. updates `VERSION` and the optional root `package.json` version;
2. creates `bump version to MAJOR.MINOR.PATCH`;
3. updates the configured release branch from development;
4. creates an annotated `vMAJOR.MINOR.PATCH` tag;
5. publishes development, release, and tag refs in one atomic push;
6. returns to `AFTER_BUMP_BRANCH`;
7. runs the post-bump hook.

For a hotfix, step 3 is replaced by two guarded operations: Bumpster first
merges the hotfix into development, then fast-forwards the release branch only
to the hotfix commit. The annotated tag points to that release-branch commit,
so unfinished development history is not published to production. Development,
release, and tag refs still use one atomic push. The hotfix branch is not pushed
or deleted automatically. `AFTER_BUMP_BRANCH` still controls the final checkout.

Bumpster does not automatically roll back a partially completed local release.
On failure it preserves state and reports recovery information. A post-bump
hook can fail after the release has already been published; its non-zero result
must not be interpreted as an unpublished release.

## Configuration

Bumpster supports:

- a global configuration at `~/.bumpsterrc`;
- a project configuration at `./.bumpsterrc`.

When both exist, the project file is selected and the global file is not
loaded or merged. Values assigned by the selected file take priority over
inherited environment values. For keys omitted by that file, an inherited
value may be used before the default.

Configuration files are sourced as Bash code in the Bumpster process. Use only
configuration files you trust.

| Key | Default | Meaning |
| --- | --- | --- |
| `GIT_MASTER_BRANCH` | `main` | Release branch name. The historical key name is retained for compatibility. |
| `GIT_DEVELOP_BRANCH` | `dev` | Development branch name. |
| `ENABLE_LOGGING` | `false` | Enables best-effort file logging when set to `true`. |
| `LOG_FILE` | `bumpster.log` | Log path; a relative path is resolved from the invocation directory. |
| `DELETE_FEATURE_BRANCH_AFTER_MERGE` | `false` | Automatically deletes a merged feature branch. |
| `ASK_BEFORE_DELETING_FEATURE_BRANCH` | `true` | Prompts before deleting a merged feature branch. |
| `SYNC_WITH_PACKAGE_JSON` | `false` | Synchronizes the root `package.json` version during a release. |
| `AFTER_BUMP_BRANCH` | configured development branch | Branch checked out after a release. |
| `BEFORE_BUMP_BRANCH` | configured development branch | Branch from which a release must start. |

Documented Boolean values are `true` and `false`.

`BUMPSTER_HOME` selects the runtime installation directory and defaults to
`$HOME/.bumpster`. A custom value must be an absolute, non-broad, non-symlink
target accepted by the installer and updater.

The installation wrapper may set `BUMPSTER_INSTALL_METHOD` to identify a
package manager. Homebrew installations set it to `homebrew`; in that mode
`--update` returns a non-zero status without changing the Cellar and directs
the user to `brew upgrade bumpster`.

## Hooks

Bumpster recognizes two executable hook names:

- `.bumpster/hooks/pre-bump` and `$BUMPSTER_HOME/hooks/pre-bump`;
- `.bumpster/hooks/post-bump` and `$BUMPSTER_HOME/hooks/post-bump`.

An executable project hook takes priority over the corresponding global hook.
Hooks receive no positional arguments and run from the repository working
directory with:

- `BUMPSTER_PREV_VERSION`;
- `BUMPSTER_NEW_VERSION`;
- `BUMPSTER_RELEASE_TYPE` (`major`, `minor`, `patch`, or `hotfix`).

`pre-bump` runs after release preflight and version calculation but before the
first mutation. A non-zero status aborts the release. `post-bump` runs after
atomic publication and the final checkout. A non-zero status makes the command
fail without undoing the published release.

## Feature branch guarantees

Feature creation is allowed only from the configured development branch.
Feature closing is rejected from the configured development branch, configured
release branch, or detached `HEAD`.

Closing a dirty feature branch requires an explicitly accepted operation-owned
stash. Bumpster includes tracked and untracked files, restores only that exact
stash on the development branch after a successful merge and push, and leaves
older stash entries untouched. If a later operation fails, the operation stash
is preserved and identified for manual recovery.

Local and remote feature deletion results are reported separately. A failed
remote deletion is a warning after the local merge, push, and deletion have
succeeded; it is never reported as a successful remote deletion.

## Exit status and output

Exit status `0` means the requested action completed according to the guarantees
above. A non-zero status means the action failed, was rejected, or completed
with a failing post-publication hook. Scripts must distinguish the
post-publication hook case using the emitted diagnostics and remote state.

Bumpster uses English CLI output and the severity labels `[INFO]`, `[WARN]`, and
`[ERROR]`. Error diagnostics are written to standard error. Exact explanatory
wording, Git subprocess output, progress ordering, and optional informational
lines are not a machine-readable API.

In an interactive terminal, release values may be highlighted with ANSI color.
Color is disabled when standard output is redirected or piped, when `TERM` is
`dumb`, or when `NO_COLOR` has a non-empty value. File logs are always plain
text without ANSI escape sequences.

The stable machine-readable version output is:

```text
Bumpster version: MAJOR.MINOR.PATCH
```

## Outside the compatibility contract

The following are implementation details unless documented elsewhere:

- internal shell functions and variables;
- test-only environment variables and file-transport overrides;
- exact log wording and timestamps;
- the order of independent informational messages;
- temporary paths, backup directory suffixes, and GitHub Actions job names.

New public surface must be documented here in English first, synchronized with
the Russian translation, covered by regression tests, and described in the
changelog.

## Independent package releases

Package mode is opt-in: run from the repository root with `bumpster --package ui
--patch` (or `--minor`, `--major`, `--hotfix`). `bumpster --package ui` asks for
one release type; `bumpster --package ui --status` validates and displays the
target without fetching or changing Git state. The modifier may precede or
follow the action. Only one package may be selected; it is not supported with
installation, configuration creation, or branch-management actions. Create a
hotfix branch with the existing `--create-hotfix`, then release it with
`--package ui --hotfix`.

Commit a declarative JSON profile at `.bumpster/packages/ui.json`:

```json
{
  "versionFile": "packages/ui/VERSION",
  "packageJson": "packages/ui/package.json",
  "tagPrefix": "ui/v"
}
```

The key uses letters, digits, underscores, or hyphens and starts with a letter
or digit. Profiles accept exactly these three fields; they are data, not shell
configuration. Node.js is required in package mode. Branches, hooks, and logging
continue to use the existing `.bumpsterrc` configuration; the profile never
changes those settings. If no `.bumpsterrc` exists, package mode uses the default
branches without creating configuration. Manifest synchronization is mandatory for the selected
package, regardless of `SYNC_WITH_PACKAGE_JSON`.

Both files and all profiles must be tracked regular files with normalized
repository-relative paths. Absolute paths, `.`/`..` components, `.git`, backslashes,
newlines, hard links, and symlinks in any path component are rejected. The version
file and `package.json` must be distinct files in the same directory below the
repository root. The manifest version must equal the bare `MAJOR.MINOR.PATCH` version file for
automatic release selection and successful status. Explicit source selection can
reconcile different valid versions; see [Canonical release version](#canonical-release-version).
All profiles are checked for overlapping files and duplicate tag prefixes. A
prefix must be a valid Git tag namespace ending in `/v`, such as `ui/v` or
`shared/ui/v`. An invalid profile blocks package mode even when another package
was selected.

The release changes only the selected version file and manifest's top-level
`version`. It creates `ui/vX.Y.Z`, rejects an existing local or remote target tag,
atomically pushes the existing development/release branch graph and the selected
tag, and returns to the configured after-bump branch. Hotfix checks compare the
selected version file across branches. A package pre-bump hook must leave HEAD,
the branch, and the worktree unchanged; a post-bump failure reports that the
release has already been published. Recovery commands use the package tag.

Hooks receive `BUMPSTER_PACKAGE`, `BUMPSTER_VERSION_FILE`, `BUMPSTER_PACKAGE_JSON`,
and `BUMPSTER_TAG` in addition to the existing version and release-type variables.
The root version, neighboring packages, dependency ranges, and lockfiles are not
updated by package releases. Committed development changes still follow the
existing branch merge policy. Bumpster does not publish npm packages.

Before releasing a dependency, explicitly decide which consumers need its new
version. Update their exact dependency versions and lockfiles as a separate,
reviewed change, run their checks, and release each affected consumer with its
own package selection. A separate CI publisher should select one package from
its tag namespace and verify its manifest version before publishing it.

Without `--package`, the current-directory `VERSION`, optional root `package.json`,
and `vX.Y.Z` tags select the ordinary product. The canonical-version policy
also applies to this flow. Package profiles never select a target implicitly.

## Canonical release version

Without a configuration file, releases use the default branches without creating
configuration. Use `--create-local-config` to create it explicitly.

This strict release policy changes the previous file-only behavior. The initial
release of each product requires an explicit source. Existing releases require a
confirmed tag; matching files alone are not sufficient.

`--version-source SOURCE` is a release-only modifier. It accepts `version-file`,
`package-json`, or `tag:NAME`, exactly once. The selected value is the **base** for
the requested bump, not the final version:

```sh
bumpster --patch --version-source tag:v1.3.0
bumpster --package website --patch --version-source tag:website/v0.0.1
bumpster --package new-package --patch --version-source version-file
```

Without `--package`, only exact stable `vMAJOR.MINOR.PATCH` tags participate.
Packages use only their profile's exact `tagPrefix` followed by stable SemVer.
Other products, prerelease tags, dependency ranges, and lockfiles do not supply
versions. The root manifest participates only when `SYNC_WITH_PACKAGE_JSON` is
true; a selected package's manifest always participates. Participating files must
be tracked regular files without symlink components or hard links. Node.js is
needed only for package profiles or participating JSON manifests.

Release preflight queries `origin` and checks its configured release branch.
Local matching tags must agree with the published tag objects. Unpublished
matching local tags stop the release for manual partial-release recovery. A
missing local copy of a published tag is allowed; its object is fetched without
creating or moving local tags. Annotated and legacy lightweight tags are accepted.

The confirmed tag is the unique latest tag by Git ancestry, not creation time,
lexical order, or a repository-wide latest release. It may be behind branch HEAD
after another product's release. All matching published tags must be ancestors
of the origin release branch and versions must increase along ancestry. Shallow
history, incomparable tag lines, multiple versions at one commit, decreasing
versions, missing release history, or conflicting local tags are hard failures.
An override cannot bypass them.

The confirmed tag must match its version file and participating manifest at its
own commit. A legacy root tag without a manifest is allowed when synchronization
is enabled later; a package tag requires both historical files. Missing historical
paths after a profile/path migration require manual migration planning. An invalid
latest tag never silently falls back to an older release.

When all participating files equal the confirmed version, it supplies the base
automatically. Any disagreement, including agreeing files ahead of the tag,
requires explicit source selection. `tag:NAME` must name the confirmed tag of the
selected product. `package-json` requires a participating manifest with a stable
version. An absent JSON `version` field can be filled only with an explicit base
from another source. Invalid JSON, non-string/invalid versions, or missing files
cannot be repaired by an override. If the selected namespace has no published or
local stable tags, an explicit file source bootstraps its first release. The new
version must exceed the last confirmed release and the selected base.

Preflight displays the files, participation, confirmed tag/commit, chosen base,
and release plan. `--status` reports files and local-cache-only tag information
without fetching; mismatching participating values return nonzero. `--version`
continues to report the installed Bumpster runtime version.

Before the first write, both CLI and package flows reject pre-bump changes to
HEAD, branch, inputs, configuration, or selected origin release refs. The hook's
`BUMPSTER_PREV_VERSION` is the selected base. All final bytes are prepared before
replacement, permissions are preserved, and one bump commit contains the final
versions. Unexpected staging outside the selected files stops before commit and
is preserved. A failed replacement restores only operation-owned writes; concurrent
edits are preserved and backup paths are reported. This is not a filesystem-wide
atomic transaction. Git publication remains atomic. Hotfix topology and branch
version checks still apply, and published refs are never rolled back automatically.
