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

**Bumpster** is a powerful utility that automates the process of semantic version bumping. The name is derived from *"bump"* and *"buster"*, reflecting its ability to quickly and easily bump the version number of your software project.

With **Bumpster**, you can easily manage the versioning of your project, ensuring that your releases are always up-to-date and properly labeled. The utility supports major, minor, and patch-level bumps for bug fixes and other changes.

## Key Features

- Automatic version bumping for major, minor, and patch versions.
- Easy integration with `git-flow` for release management.
- Customizable branch names for `master` and `develop`.
- Optional logging of all operations to a log file.
- Minimal footprint: installs in `~/.bumpster` directory, similar to **rbenv**.
- Clean removal: to uninstall, simply delete the `.bumpster` directory.
- Works on Linux, macOS, and Git Bash on Windows.

## Installation

You can install Bumpster with a single command:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/phoenixweiss/bumpster/main/install.sh)"
```

This will download and install Bumpster in your home directory under `~/.bumpster`.

After installation, add Bumpster to your PATH by running the following command:

```bash
echo 'export PATH="$HOME/.bumpster/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

For **Git Bash on Windows**, use:

```bash
echo 'export PATH="$HOME/.bumpster/bin:$PATH"' >> ~/.bash_profile
source ~/.bash_profile
```

## Usage

Once installed, Bumpster is available as a command-line tool. You can bump your project's version, customize branch names, enable logging, check the version of Bumpster itself, or get help with the following commands:

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

To display help and see available options:

```bash
bumpster --help
# or
bumpster -h
```

If a newer version is available, it will be indicated next to the version number in the help output.

### Updating Bumpster

To update Bumpster to the latest version, run:

```bash
bumpster --update
# or
bumpster -u
```

This will download and replace the existing installation with the latest version.

### Customizing Branch Names

You can specify custom branch names for `master` and `develop` branches by providing a configuration file or setting them via environment variables. By default, Bumpster uses `master` and `develop`, but you can change them like this:

```bash
bumpster --branch-master main --branch-develop dev
```

Alternatively, set them in the configuration file `~/.bumpsterrc` or a local config `.bumpsterrc` in the project directory:

```bash
# ~/.bumpsterrc or ./your_project/.bumpsterrc
GIT_MASTER_BRANCH="main"
GIT_DEVELOP_BRANCH="dev"
```

### Enabling Logging

Bumpster supports optional logging. To enable logging of all operations to `bumpster.log`, add the following line to the configuration file:

```bash
ENABLE_LOGGING="true"
```

Once enabled, Bumpster will create and append logs to `bumpster.log` in the current directory.

### Creating a local configuration file

To create a local `.bumpsterrc` configuration file in your current project directory, run:

```bash
bumpster --create-local-config
```

This will guide you through an interactive setup process and generate a `.bumpsterrc` file in the current directory.

## Configuration

Bumpster uses a configuration file (`.bumpsterrc`) to store customizable options like branch names and logging settings. There are two types of configuration files:

- **Global Configuration**: Located in `~/.bumpsterrc`, applies to all projects.
- **Local Configuration**: Located in the root of a project (`./your_project/.bumpsterrc`), has higher priority over the global config.

Example configuration:

```bash
# ~/.bumpsterrc or ./your_project/.bumpsterrc
GIT_MASTER_BRANCH="main"
GIT_DEVELOP_BRANCH="dev"
ENABLE_LOGGING="true"
```

## Requirements

- [curl](https://curl.se/)
- [bash](https://www.gnu.org/software/bash/)
- [git](https://git-scm.com/)
- [git-flow](https://danielkummer.github.io/git-flow-cheatsheet/index.html)

Before using Bumpster, ensure that `git-flow` is installed and initialized using:

```bash
git flow init
```

## Uninstalling Bumpster

To completely remove Bumpster, simply delete the `~/.bumpster` directory:

```bash
rm -rf ~/.bumpster
```

## License

Bumpster is open-source and available under the MIT license.
