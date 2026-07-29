# Changelog

All notable changes to Bumpster are documented in this file. English is the
canonical language for release notes. Git tags remain the source of truth for
releases before `0.7.0`, which are not reconstructed here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A canonical English CLI compatibility contract with a synchronized Russian
  translation, covering commands, configuration, hooks, exit semantics, side
  effects, and safety guarantees intended for `1.x`.
- Regression coverage for the documented help/version surface and rejection of
  ambiguous action selections.

### Changed

- CLI action options are now mutually exclusive and parsed before dispatch, so
  combinations such as `--status --patch` or `--major --minor` fail without
  mutation instead of depending on argument order.
- Help now distinguishes the historical `GIT_MASTER_BRANCH` key as the release
  branch and describes custom development-branch defaults precisely.

## [0.9.2] - 2026-07-29

### Added

- Isolated integration coverage for configuration precedence, custom release
  branch defaults, hook priority and version variables, release-flow
  delegation, and failure handling in configuration, logging, and feature
  branch operations.

### Changed

- Release orchestration is split into explicit planning and execution
  functions, keeping preflight validation before local mutations and removing
  redundant branch checkouts from the top-level CLI flow.
- `--status` now loads the selected project or global configuration before
  classifying custom branches and reports unavailable upstream information
  without exposing raw Git failures.
- English and Russian documentation now define the canonical command,
  configuration precedence, release behavior, requirements, hook timing,
  language policy, and safe uninstall boundaries consistently.

### Fixed

- Custom development branches now provide the default values for
  `BEFORE_BUMP_BRANCH` and `AFTER_BUMP_BRANCH`.
- Selected configuration load failures and configuration write failures stop
  the command instead of continuing or reporting false success.
- An unavailable optional log file produces one warning without replacing the
  primary command result.
- Feature creation reports an unresolved or detached `HEAD` clearly, while
  feature closing checks Git state explicitly and never reports a rejected
  remote branch deletion as successful.

## [0.9.1] - 2026-07-28

### Added

- Cross-platform public Release smoke tests for checksum, provenance, runtime
  contents, clean installation, migration from `v0.8.0`, and no-op self-update.
- Automatic public smoke verification after each published Release, plus a
  manual GitHub Actions entry point without recurring scheduled runs.

## [0.9.0] - 2026-07-28

### Added

- A reproducible runtime packager that builds a versioned archive from an
  explicit Git-ref whitelist and emits `SHA256SUMS`.
- An acceptance test proving repeated builds are byte-identical, the packaged
  CLI is executable, and no documentation, tests, CI, installer, or development
  files enter the runtime archive.
- SLSA build provenance for the runtime archive, generated with GitHub artifact
  attestations and verified before release publication.
- Isolated install and self-update coverage for clean installation, migration
  from `0.8.0`, repeated installation, unavailable or corrupt assets, unsafe
  target paths, no-op and downgrade handling, and rollback after activation
  failures.

### Changed

- The release workflow now creates a draft, uploads and verifies the exact
  runtime archive and checksum assets, and only then publishes it as the latest
  GitHub Release.
- The installation guide now defines a one-time migration path from the legacy
  `0.8.x` source-archive updater to the verified Release-asset scheme.
- Installation and self-update now stage the latest stable runtime asset,
  validate its checksum and exact structure, preserve user hooks, retain the
  previous runtime in a collision-safe backup, and restore it after a failed
  activation.

### Fixed

- Update failures now return a non-zero CLI status, and generated wrappers
  retain custom or physically canonicalized `BUMPSTER_HOME` paths.
- Help output no longer depends on a network request to the mutable `main`
  branch to display the installed version.
- Runtime packaging, installation, and self-update accept either `shasum` or
  `sha256sum`, including the tools available in Git Bash.
- Windows self-update releases the running installation before activating the
  verified runtime, avoiding file-lock failures during the transactional rename.
- Cross-platform install fixtures retain the historical migration tag, preserve
  the Git Bash `curl` path, and use native Windows file URLs.

## [0.8.5] - 2026-07-27

### Changed

- Closing a feature branch with uncommitted changes now requires an explicit
  operation-owned stash, including untracked files. Declining the stash aborts
  before any checkout or merge.
- After a successful merge and push, the operation-owned stash is restored with
  its staged state on the configured development branch.
- Optional `package.json` synchronization now uses Node.js to parse JSON and
  atomically replace the file from a unique temporary file in the same
  directory.

### Fixed

- Existing user stashes are never selected by message or position when closing
  a feature branch. Bumpster tracks its exact stash commit, removes only that
  entry after a successful restore, and reports its ID if a later step fails.
- Package synchronization changes or adds only the root `version` field,
  preserves nested version fields and file permissions, removes temporary
  files, and rejects invalid JSON before any release mutation.

## [0.8.4] - 2026-07-27

### Added

- Release failure diagnostics that preserve local state, compare current remote
  refs with their preflight values, and print safe inspection or retry commands
  without performing an automatic rollback.

### Changed

- Release preflight now requires an existing stable `MAJOR.MINOR.PATCH` value in
  `VERSION`, a configured and reachable `origin`, matching upstreams for local
  release branches, and fetched tracking refs for remote release branches.
- Failed atomic publication no longer assumes that remote refs are unchanged;
  Bumpster verifies them before suggesting a retry.

## [0.8.3] - 2026-07-27

### Added

- A pinned ShellCheck `0.11.0` development workflow and a single local quality
  command for Bash syntax and static analysis.
- GitHub Actions quality checks on Linux and macOS, plus the full integration
  suite on Linux, macOS, and Windows with Git Bash.
- Workflow validation with actionlint and weekly GitHub Actions updates through
  Dependabot.
- Automated GitHub Release publication after all required checks pass for a
  matching annotated semantic-version tag.
- A canonical English changelog with verified release notes for the key
  `0.7.0` through `0.8.2` milestones.
- A retrospective GitHub Release for `v0.8.2`, establishing the release history
  before automated publication begins.
- CI and latest-release badges in the English and Russian documentation.

### Changed

- The CI workflow can be reused as the release workflow's required quality gate.
- Release descriptions use a reviewed CHANGELOG section followed by GitHub's
  generated pull-request and contributor summary.

### Fixed

- Integration fixtures compare canonical local paths, including the different
  drive-path forms used by Git and Git Bash on Windows.

## [0.8.2] - 2026-07-27

### Added

- Expanded the isolated release test suite to 18 scenarios covering successful
  bumps, hooks, branch and tag state, remote divergence, tracking branches, and
  rejected publication.

### Changed

- Added a release preflight that fetches current origin refs before hooks or
  local mutations and rejects stale, divergent, or incomplete release state.
- Publishes the development branch, main branch, and annotated release tag in
  one atomic push.

### Fixed

- Creates a local tracking branch from an existing remote-only release branch
  instead of creating it from the current `HEAD`.
- Prevents a rejected main update from leaving development or tag refs partially
  published on the remote.

This release contains source archives generated by GitHub and does not include a
standalone Bumpster runtime asset.

## [0.8.1] - 2026-07-26

### Added

- Added the first isolated integration harness for release scenarios. Each test
  uses a temporary worktree, a separate home directory, and a local bare remote
  instead of the real repository origin.
- Covered the initial patch release, dirty-tree rejection, wrong-branch
  rejection, failing pre-bump hook, and existing-tag rejection scenarios.

## [0.8.0] - 2025-11-28

### Added

- Added `BEFORE_BUMP_BRANCH` and require release bumps to start from the
  configured branch.
- Added project and global `pre-bump` and `post-bump` hooks with previous and new
  versions exposed through environment variables.
- Added severity-aware logging and clearer command failures.

### Changed

- Improved update, branch, and feature-flow error handling.
- Documented release preflight expectations and the hooks API in English and
  Russian.

## [0.7.0] - 2025-11-28

### Changed

- Changed the default post-release branch to the configured development branch.
- Made feature commands load project or global configuration before validating
  branch names.
- Aligned status and feature-flow behavior with configured main and development
  branches.

### Fixed

- Correctly writes the package synchronization option during interactive setup.
- Removed duplicated feature-branch deletion checks and improved related error
  handling.

[Unreleased]: https://github.com/phoenixweiss/Bumpster/compare/v0.9.2...HEAD
[0.9.2]: https://github.com/phoenixweiss/Bumpster/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/phoenixweiss/Bumpster/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/phoenixweiss/Bumpster/compare/v0.8.5...v0.9.0
[0.8.5]: https://github.com/phoenixweiss/Bumpster/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/phoenixweiss/Bumpster/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/phoenixweiss/Bumpster/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/phoenixweiss/Bumpster/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/phoenixweiss/Bumpster/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/phoenixweiss/Bumpster/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/phoenixweiss/Bumpster/compare/v0.6.3...v0.7.0
