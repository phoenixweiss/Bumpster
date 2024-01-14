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

**Bumpster** is a powerful utility that automates the process of semantic version bumping. The name is derived from *"bump"* and *"buster"* reflecting its ability to quickly and easily bump the version number of your software project.

With **Bumpster**, you can easily manage the versioning of your project, ensuring that your releases are always up-to-date and properly labeled. The utility supports both major and minor version bumps, as well as patch-level bumps for bug fixes and other minor changes.

It designed to be easy to use, with a simple command-line interface (CLI) that allows you to quickly and easily bump your project's version number. Whether you're working on an open-source project or a commercial software product, **Bumpster** is the perfect tool for managing your versioning process.

Many features are planned for upcoming releases.

## Requirements

- [bash](https://www.gnu.org/software/bash/)
- [git](https://git-scm.com/)
- [git-flow](https://danielkummer.github.io/git-flow-cheatsheet/index.html)
- [awk](https://wikipedia.org/wiki/AWK)

Before use, make sure to give execute permissions: `chmod +x bumpster.sh`.

Also, you need to make sure that `git-flow` is installed and initialized using `git flow init`.

The script `bumpster.sh` pulls the current version tag of the application from the `VERSION` file and bumps it. The script asks what needs to be bumped: major, minor, or patch version (by default).

In addition, you can automatically pass the version type to be bumped as parameters when running the script:

```sh
# # Bump major version:
./bumpster.sh --major
# or
./bumpster.sh -M

# Bump minor version:
./bumpster.sh --minor
# or
./bumpster.sh -m

# Bump patch version:
./bumpster.sh --patch
# or
./bumpster.sh -p
```
