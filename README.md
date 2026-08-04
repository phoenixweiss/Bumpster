# Bumpster

[![CI](https://github.com/phoenixweiss/Bumpster/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/phoenixweiss/Bumpster/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/phoenixweiss/Bumpster?display_name=tag&sort=semver)](https://github.com/phoenixweiss/Bumpster/releases/latest)

```ascii
    _____                                 __
   / _  / __  __ ____ ___   ____   _____ / /_ ___   _____
  / __  |/ / / // __ `__ \ / __ \ / ___// __// _ \ / ___/
 / /_/ // /_/ // / / / / // /_/ /(__  )/ /_ / ___// /
/_____/ \__,_//_/ /_/ /_// .___//____/ \__/ \___//_/
                        /_/
```

[WEBSITE](https://phoenixweiss.github.io/Bumpster/) ·
[RUSSIAN VERSION](README_RU.md)

**Bumpster** is a powerful utility for automating semantic version management. The name combines *"bump"* and *"buster"*, highlighting its ability to quickly and efficiently handle version bumps for your software projects.

## Key Features

- Supports automatic version bumping for **major**, **minor**, and **patch** updates.
- Works seamlessly with Git for release management without requiring `git-flow`.
- Configurable branch names for `master` and `develop`.
- Feature branch creation and closing with customizable behavior.
- Local and global configuration files for flexibility.
- Optional logging for supported operations.
- Custom hooks (pre-bump/post-bump) for project-specific workflows.
- Minimal footprint: managed by Homebrew or installed under `~/.bumpster`.
- Easy removal through Homebrew or by deleting the standalone directory.
- Cross-platform compatibility (Linux, macOS, and Git Bash on Windows).
- Supports optional synchronization of the `VERSION` file with `package.json`.

## Installation

### Homebrew

On macOS or Linux with Homebrew, install Bumpster from its official tap:

```bash
brew install phoenixweiss/bumpster/bumpster
```

This single command adds the `phoenixweiss/bumpster` tap and installs the
latest stable release. The fully qualified name trusts only the selected
Formula, not the whole third-party tap.

To use the shorter command, add the tap and explicitly trust the Bumpster
Formula first:

```bash
brew tap phoenixweiss/bumpster
brew trust --formula phoenixweiss/bumpster/bumpster
brew install bumpster
```

Homebrew provides both `bumpster` and `bump`, keeps the runtime in its Cellar,
and manages upgrades and removal without requiring a manual PATH change.

Without the explicit Formula trust above, the unqualified
`brew install bumpster` works on a fresh Homebrew installation only after
Bumpster is accepted into `homebrew-core`. Until then, the fully qualified
one-command install is the simplest option.

### Standalone installer

For Linux, macOS, Git Bash, or systems where you do not want to use Homebrew,
install Bumpster with:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/phoenixweiss/Bumpster/main/install.sh)"
```

This installs Bumpster in your home directory under `~/.bumpster`.
The installer downloads only the runtime archive and `SHA256SUMS` from the
latest stable GitHub Release. It verifies the checksum, exact archive contents,
regular-file structure, embedded version, and a CLI smoke test before changing
the installation directory. `curl`, `tar`, and either `shasum` or `sha256sum`
are required.

After installation, add Bumpster to your PATH:

```bash
echo 'export PATH="$HOME/.bumpster/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

For **Git Bash on Windows**:

```bash
echo 'export PATH="$HOME/.bumpster/bin:$PATH"' >> ~/.bash_profile
source ~/.bash_profile
```

The installer always creates the `bumpster` command wrapper. It also creates
the shorter `bump` wrapper when that command name is not already in use. The
examples below use `bumpster` as the canonical command; every shown `bump`
variant is an optional equivalent.

### Migrating from 0.8.x

Versions through `0.8.x` use the legacy updater: it downloads the source archive
of the `main` branch and replaces the entire `~/.bumpster` directory. Do not use
the old `bumpster --update` command for the one-time transition to `0.9.0`,
especially if you keep custom hooks in `~/.bumpster/hooks`.

The verified migration path is available starting with `v0.9.0`. Before the
first transition, keep a separate copy of the existing installation:

```bash
backup_dir="$HOME/.bumpster-backup-$(date +%Y%m%d-%H%M%S)"
cp -R "$HOME/.bumpster" "$backup_dir"
printf 'Backup: %s\n' "$backup_dir"
```

Then run the installer pinned to the first asset-based release:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/phoenixweiss/Bumpster/v0.9.0/install.sh)"
bumpster --version
```

The `0.9.0` installer downloads and verifies the versioned GitHub Release
runtime asset in a temporary sibling directory. It preserves user hooks and
configuration, moves the previous runtime to a uniquely named backup, and
automatically restores it if activation or wrapper creation fails. After this
one-time migration, future `bumpster --update` operations use the same verified
Release-asset scheme. Global `~/.bumpsterrc` and project-level `.bumpsterrc`
files are outside the runtime directory and remain in place.

The successful migration prints the automatic backup path. Keep it until the
new version, hooks, and configuration have been checked; it can then be removed
manually. The pinned installer and its runtime assets remain available in the
[v0.9.0 GitHub Release](https://github.com/phoenixweiss/Bumpster/releases/tag/v0.9.0).

## Usage

The public commands, configuration keys, hooks, exit semantics, and safety
guarantees are defined in the
[CLI compatibility contract](docs/CLI_CONTRACT.md).

### Release Pre-flight Checks

Before running `--major`, `--minor`, `--patch`, or the interactive release flow:

- Ensure you are inside an initialized Git repository (`git rev-parse --git-dir` should print the `.git` path and exit without errors).
- Ensure `VERSION` exists and contains a stable semantic version in the exact
  `MAJOR.MINOR.PATCH` format, without a `v` prefix, prerelease suffix, or leading
  zeros.
- Make sure your working tree is clean. `bumpster.sh` refuses to run if there are unstaged or uncommitted changes to prevent accidental data loss.
- Double-check that the active branch matches your configured
  `BEFORE_BUMP_BRANCH` (the configured development branch, `dev` by default);
  Bumpster aborts otherwise to keep releases consistent.
- Make sure `origin` is configured and reachable. Each local release branch must
  track its matching branch on that remote, such as `dev` tracking `origin/dev`
  and `main` tracking `origin/main`.
- Before changing files, Bumpster fetches the current `origin` refs, rejects a
  local development branch that is behind or diverged, and verifies that local
  `main` matches `origin/main`.
- Make sure the target release tag does not already exist locally or on `origin`.

The development branch, main branch, and release tag are published with one
atomic push. If the remote rejects any of these refs, none of them are updated.
If a release stops after creating local state, Bumpster does not roll it back
automatically. It reports the current branch, commit, worktree and tag state,
compares the remote refs with their preflight values, and prints safe inspection
commands. A retry command is shown only when a rejected atomic publication left
the remote refs unchanged.

### Bumping Versions

Running `bumpster` without an option starts the release flow and asks for
`major`, `minor`, or `patch`; pressing Enter selects `patch`. Use an explicit
version option in automation and whenever the intended bump should be
unambiguous.

**Bump major version**:

```bash
bumpster --major
# or
bump -M
```

**Bump minor version**:

```bash
bumpster --minor
# or
bump -m
```

**Bump patch version**:

```bash
bumpster --patch
# or
bump -p
```

### Synchronizing with package.json

Bumpster supports optional synchronization between the `VERSION` file and
`package.json`. When enabled, a release command synchronizes only the root
`version` field; nested fields named `version` are left unchanged. If the root
field is missing, it is added.

Synchronization requires an executable Node.js installation. Bumpster parses
and validates the JSON before any release mutation, preserves the existing
indentation style, line ending and file permissions, then replaces
`package.json` atomically through a unique temporary file in the same directory.
Invalid JSON or a non-string root `version` aborts the release without changing
`VERSION` or `package.json`. If `package.json` is not found, synchronization is
skipped with a log message.

**Example Configuration**:

```bash
SYNC_WITH_PACKAGE_JSON="true"
```

**Example Usage**:

- `VERSION` updated to `1.0.0`
- `package.json` updated with the same version:

  ```json
  {
    "version": "1.0.0"
  }
  ```

### Display Version

To display the current version of Bumpster:

```bash
bumpster --version
# or
bump -v
```

### Display Help

For help and available options:

```bash
bumpster --help
# or
bump -h
```

### Updating Bumpster

After migrating to `0.9.0` or later, update Bumpster to the latest stable
version:

```bash
bumpster --update
# or
bump -u
```

If `bumpster --version` reports `0.8.x`, follow
[Migrating from 0.8.x](#migrating-from-08x) instead of running the legacy
updater.

The updater first validates the latest stable Release in a temporary sibling
directory. It preserves `~/.bumpster/hooks`, activates the new runtime with
rename operations, recreates the command wrappers, and retains the previous
runtime at the backup path printed on success. Any failure after activation
starts restores the previous installation and returns a non-zero status.

For a Homebrew installation, use `brew upgrade bumpster`. The `--update`
command does not replace files managed by Homebrew and instead points back to
that command.

### Customizing Branch Names

You can specify custom branch names in a configuration file. Default branch
names are `main` and `dev`.

Example configuration in `.bumpsterrc`:

```bash
# ~/.bumpsterrc or ./project/.bumpsterrc
GIT_MASTER_BRANCH="main"
GIT_DEVELOP_BRANCH="dev"
ENABLE_LOGGING="true"
LOG_FILE="bumpster.log"
DELETE_FEATURE_BRANCH_AFTER_MERGE="false"
ASK_BEFORE_DELETING_FEATURE_BRANCH="true"
SYNC_WITH_PACKAGE_JSON="true"
AFTER_BUMP_BRANCH="dev"
BEFORE_BUMP_BRANCH="dev"
```

If the selected local or global configuration cannot be loaded, Bumpster stops
instead of continuing with partially applied values. File logging is
best-effort: an unwritable `LOG_FILE` produces one warning, while the primary
command continues and keeps its own exit status.

### AFTER_BUMP_BRANCH option

This option allows you to specify the branch to switch to after a version bump. By default, it switches back to the development branch (so you can resume work in `dev` right after tagging a release). If the specified branch does not exist, it falls back to the configured development branch.

**Example**:

```bash
AFTER_BUMP_BRANCH="dev"
```

### BEFORE_BUMP_BRANCH option

This option defines the branch you must be on before starting a release. By
default it expects the development branch. Bumpster validates that the
configured branch exists locally and that you are currently on it, aborting
otherwise so every release starts from the correct branch.

### Checking Repository Status

To check the current repository status:

```bash
bumpster --status
# or
bump -s
```

This displays:

- Current branch and whether it matches the configured development or release
  branch.
- Number of uncommitted changes.
- Number of unpushed commits when the current branch has a resolvable upstream;
  otherwise an explicit unavailable status.

Run this command inside a Git repository. It is read-only and does not start a
release. Bumpster loads the selected local or global configuration before
classifying the current branch.

### Creating a Local Configuration File

Generate a local `.bumpsterrc` configuration file in your project:

```bash
bumpster --create-local-config
# or
bump -l
```

This guides you through an interactive setup process. If the configuration
cannot be written, the command returns a non-zero status and does not report
successful creation.

### Creating and Closing Feature Branches

**Create a feature branch**:

```bash
bumpster --create-feature
# or
bump -f
```

This command must be executed from your configured development branch (default `dev`). Bumpster validates the current branch and aborts otherwise, ensuring feature branches always fork from the correct base. Branch names may contain alphanumeric characters plus `/`, `_`, and `-`.

**Close the current feature branch**:

```bash
bumpster --close-feature
# or
bump -c
```

When closing a feature branch, changes are merged into the development branch, and the feature branch is optionally deleted based on configuration.
If the working tree contains uncommitted changes, Bumpster offers to stash both
tracked and untracked files. Declining aborts before checkout or merge. After a
successful merge and push, only the stash created by that invocation is restored
with its staged state on the configured development branch; existing stashes
remain untouched. If a later operation fails, Bumpster preserves the created
stash and reports its exact commit ID for manual recovery.
When branch deletion is enabled, local and remote deletion results are reported
separately. A rejected remote deletion is warned about and is never reported as
successful.

### Custom Hooks

You can extend Bumpster by providing executable scripts in `.bumpster/hooks/`
inside your project (or `~/.bumpster/hooks/` for global hooks). An executable
project hook takes priority over a global hook with the same name. The following
hook names are supported:

- `pre-bump` - runs after release preflight and version calculation, but before
  files are updated or committed.
- `post-bump` - runs after the atomic push and the final branch checkout.

Hooks receive the environment variables `BUMPSTER_PREV_VERSION` and
`BUMPSTER_NEW_VERSION` so they can inspect both versions. A non-zero
`pre-bump` status aborts before the first release mutation. A non-zero
`post-bump` status makes the command fail, but the already published branches
and tag are not rolled back.

**Example use-cases**

- `pre-bump`: lint or validate files before committing, for example:

  ```bash
  #! /bin/bash
  npm run test || exit 1
  ```

  Returning a non-zero exit code prevents the bump if tests fail.

- `post-bump`: notify your team or trigger CI:

  ```bash
  #! /bin/bash
  echo "New release $BUMPSTER_NEW_VERSION is ready" | mail -s "Bumpster" devs@example.com
  ```

## Configuration

Bumpster uses configuration files (`.bumpsterrc`) to customize its behavior. It
supports two locations:

- **Global Configuration**: Located in `~/.bumpsterrc`.
- **Local Configuration**: Located in the project directory (`./.bumpsterrc`).

When both files exist, Bumpster selects the local file and does not load or
merge the global file. Exported variables with the same names can provide
values omitted by the selected file, but values assigned in that file take
priority.

### Example Configuration

```bash
# ~/.bumpsterrc or ./project/.bumpsterrc
GIT_MASTER_BRANCH="main"
GIT_DEVELOP_BRANCH="dev"
ENABLE_LOGGING="true"
LOG_FILE="bumpster.log"
DELETE_FEATURE_BRANCH_AFTER_MERGE="false"
ASK_BEFORE_DELETING_FEATURE_BRANCH="true"
SYNC_WITH_PACKAGE_JSON="true"
AFTER_BUMP_BRANCH="dev"
BEFORE_BUMP_BRANCH="dev"
```

## Requirements

- [Bash](https://www.gnu.org/software/bash/) and
  [Git](https://git-scm.com/) for the CLI.
- [curl](https://curl.se/), `tar`, and either `shasum` or `sha256sum` for
  installation and self-update.
- Node.js only when `SYNC_WITH_PACKAGE_JSON="true"`.
- GitHub CLI only for optional manual attestation verification.

Release, status, and feature-branch commands must be run inside an initialized
Git repository.

## Development and Testing

The project uses the ShellCheck version recorded in `.shellcheck-version`.
Install that version before running the quality checks. On macOS with Homebrew:

```bash
brew install shellcheck
```

For other platforms, use the packages from the
[official ShellCheck release](https://github.com/koalaman/shellcheck/releases/latest).
Then run the syntax and static analysis checks from the project root:

```bash
./scripts/quality.sh
```

To check Bash syntax without requiring ShellCheck:

```bash
./scripts/quality.sh --syntax-only
```

Run the integration suite separately:

```bash
./tests/run.sh
```

Build the versioned runtime archive and `SHA256SUMS` from a committed Git ref
with:

```bash
./scripts/build-runtime.sh /tmp/bumpster-dist HEAD
```

The archive is generated from an explicit whitelist and contains only
`bumpster.sh`, `config.sh`, `VERSION`, `LICENSE`, and the required `lib/` files.
It excludes the installer, documentation, tests, CI configuration, development
files, and website source. Repeated builds of the same ref produce the same
archive bytes.

Release notes are maintained in the canonical English `CHANGELOG.md`. Preview
the notes that would be published for a version with:

```bash
./scripts/release-notes.sh 1.0.0
```

Each scenario creates a temporary working repository, an isolated `HOME`, and a
local bare remote. The suite never uses the project's real `origin`. To preserve
the temporary repositories for inspection after a run:

```bash
KEEP_TEST_TMP=true ./tests/run.sh
```

The recommended VS Code extension is listed in `.vscode/extensions.json` and
uses the repository-level `.shellcheckrc` configuration.

GitHub Actions runs the ShellCheck checks on Linux and macOS, validates the
workflow files with actionlint, and runs the integration suite on Linux, macOS,
and Windows with Git Bash. A matching annotated `vMAJOR.MINOR.PATCH` tag starts
the release workflow, which publishes the GitHub Release only after the same
required checks pass. Starting with `0.9.0`, the workflow builds the runtime
archive from the tagged commit, verifies its checksum and exact contents,
generates SLSA build provenance, and uploads only the archive and `SHA256SUMS` to
a draft Release. The Release becomes public and latest only after its assets
have been verified. After publication, a separate matrix smoke test downloads
the public latest Release on Linux, macOS, and Windows/Git Bash; it verifies the
checksum and attestation, clean installation, migration from `v0.8.0`, safe CLI
commands, no-op self-update, and the installed file whitelist. The same smoke
workflow can be started manually and does not run on a recurring schedule.

After downloading both runtime assets, verify the checksum and the GitHub
artifact attestation with:

```bash
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c SHA256SUMS
else
  sha256sum -c SHA256SUMS
fi
gh attestation verify bumpster-X.Y.Z.tar.gz --repo phoenixweiss/Bumpster
```

The checksum verifies the downloaded bytes. The attestation additionally ties
the runtime archive to the Bumpster repository and its GitHub Actions build.

### Documentation Languages

English is the canonical language for source comments, CLI output, configuration
examples, `README.md`, `CHANGELOG.md`, GitHub Release notes, and the primary
website. Russian is the first maintained additional language in
`README_RU.md` and the
[Russian website locale](https://phoenixweiss.github.io/Bumpster/ru/).

Write user-facing documentation in English first, then update the Russian
version with the same meaning in the same change. Future translations must use
English as their source and fall back to English when incomplete; do not mix
languages inside one interface without an explicit locale switch. New commit
messages use short, simple English.

## Uninstalling Bumpster

Remove a Homebrew installation with:

```bash
brew uninstall bumpster
```

Remove a standalone installation and its command wrappers with:

```bash
rm -rf -- "$HOME/.bumpster"
```

The global configuration file `~/.bumpsterrc`, project-level `.bumpsterrc`
files, and versioned backup directories are intentionally outside that path.
Remove them separately only after checking that they are no longer needed.

## Author

Created and maintained by [Pavel Tkachev (@phoenixweiss)](https://github.com/phoenixweiss).

## License

Bumpster is open-source software available under the MIT license.
