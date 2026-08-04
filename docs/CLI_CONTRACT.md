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
| `-M`, `--major` | Yes | Runs a major release. |
| `-m`, `--minor` | Yes | Runs a minor release. |
| `-p`, `--patch` | Yes | Runs a patch release. |

Help, version, update, and local configuration creation do not require a Git
repository. Status, feature operations, and releases do.

## Release guarantees

A release requires:

- a clean working tree;
- a valid `MAJOR.MINOR.PATCH` value in `VERSION`;
- the configured `BEFORE_BUMP_BRANCH` checked out locally;
- distinct configured development and release branches;
- correct `origin` upstreams for existing release branches;
- reachable and current remote refs;
- no local or remote tag for the target version.

The release plan and package synchronization input are validated before the
pre-bump hook and before the first release mutation. A successful release:

1. updates `VERSION` and the optional root `package.json` version;
2. creates `bump version to MAJOR.MINOR.PATCH`;
3. fast-forwards the configured release branch from development;
4. creates an annotated `vMAJOR.MINOR.PATCH` tag;
5. publishes development, release, and tag refs in one atomic push;
6. returns to `AFTER_BUMP_BRANCH`;
7. runs the post-bump hook.

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
- `BUMPSTER_NEW_VERSION`.

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
