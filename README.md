# Bumpster

```ascii
    _____                                 __
   / _  / __  __ ____ ___   ____   _____ / /_ ___   _____
  / __  |/ / / // __ `__ \ / __ \ / ___// __// _ \ / ___/
 / /_/ // /_/ // / / / / // /_/ /(__  )/ /_ / ___// /
/_____/ \__,_//_/ /_/ /_// .___//____/ \__/ \___//_/
                        /_/
```

[RUSSIAN VERSION](README_RU.md)

**Bumpster** is a powerful utility for automating semantic version management. The name combines *"bump"* and *"buster"*, highlighting its ability to quickly and efficiently handle version bumps for your software projects.

## Key Features

- Supports automatic version bumping for **major**, **minor**, and **patch** updates.
- Works seamlessly with Git for release management without requiring `git-flow`.
- Configurable branch names for `master` and `develop`.
- Feature branch creation and closing with customizable behavior.
- Local and global configuration files for flexibility.
- Optional logging for all operations.
- Minimal footprint: installed in `~/.bumpster`.
- Easy removal: delete the `.bumpster` directory to uninstall.
- Cross-platform compatibility (Linux, macOS, and Git Bash on Windows).

## Installation

Install Bumpster with a single command:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/phoenixweiss/Bumpster/main/install.sh)"
```

This installs Bumpster in your home directory under `~/.bumpster`.

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

## Usage

### Bumping Versions

**Bump major version**:

```bash
bumpster --major
# or
bumpster -M
```

**Bump minor version**:

```bash
bumpster --minor
# or
bumpster -m
```

**Bump patch version**:

```bash
bumpster --patch
# or
bumpster -p
```

### Display Version

To display the current version of Bumpster:

```bash
bumpster --version
# or
bumpster -v
```

### Display Help

For help and available options:

```bash
bumpster --help
# or
bumpster -h
```

### Updating Bumpster

Update Bumpster to the latest version:

```bash
bumpster --update
# or
bumpster -u
```

### Customizing Branch Names

You can specify custom branch names by providing a configuration file or environment variables. Default branch names are `main` and `dev`.

Example configuration in `.bumpsterrc`:

```bash
# ~/.bumpsterrc or ./project/.bumpsterrc
GIT_MASTER_BRANCH="main"
GIT_DEVELOP_BRANCH="dev"
ENABLE_LOGGING="true"
DELETE_FEATURE_BRANCH_AFTER_MERGE="false"
ASK_BEFORE_DELETING_FEATURE_BRANCH="true"
LOG_FILE="bumpster.log"
```

### Checking Repository Status

To check the current repository status:

```bash
bumpster --status
```

This displays:

- Current branch.
- Number of uncommitted changes.
- Number of unpushed commits.

### Creating a Local Configuration File

Generate a local `.bumpsterrc` configuration file in your project:

```bash
bumpster --create-local-config
```

This guides you through an interactive setup process.

### Creating and Closing Feature Branches

**Create a feature branch**:

```bash
bumpster --create-feature
# or
bumpster -f
```

**Close the current feature branch**:

```bash
bumpster --close-feature
# or
bumpster -c
```

When closing a feature branch, changes are merged into the development branch, and the feature branch is optionally deleted based on configuration.

## Configuration

Bumpster uses configuration files (`.bumpsterrc`) to customize its behavior. It supports two types of configuration files:

- **Global Configuration**: Located in `~/.bumpsterrc`.
- **Local Configuration**: Located in the project directory (`./.bumpsterrc`). Local configurations override global ones.

## Requirements

- [curl](https://curl.se/)
- [bash](https://www.gnu.org/software/bash/)
- [git](https://git-scm.com/)

Before using Bumpster, ensure you have an initialized Git repository.

## Uninstalling Bumpster

To completely remove Bumpster, delete the `~/.bumpster` directory:

```bash
rm -rf ~/.bumpster
```

## Author

Created and maintained by **PAVEL TKACHEV (phoenixweiss)**.

## License

Bumpster is open-source software available under the MIT license.
