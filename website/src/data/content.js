export const installCommand =
  '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/phoenixweiss/Bumpster/main/install.sh)"';

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

export const content = {
  en: {
    skip: "Skip to content",
    nav: {
      why: "Why Bumpster",
      flow: "Release flow",
      commands: "Commands",
      github: "GitHub",
      language: "Русский",
      languageLabel: "Open Russian version",
    },
    hero: {
      eyebrow: "SEMANTIC VERSIONING · GIT RELEASES · BASH",
      title: ["Release versions", "with ease"],
      lead: "Bumpster checks your Git state, updates the version, creates the tag, and publishes every release ref in one guarded flow.",
      install: "Install Bumpster",
      explore: "See the release flow",
      note: "Linux · macOS · Git Bash",
    },
    terminal: {
      label: "release.sh",
      select: "Select a release type",
      prompt: "$",
    },
    facts: [
      ["RUNTIME", "Bash + Git"],
      ["SAFETY", "Atomic Git push"],
      ["INSTALL", "Verified Release asset"],
      ["LICENSE", "MIT"],
    ],
    why: {
      eyebrow: "WHY BUMPSTER",
      title: "The boring parts of a release should stay boring.",
      intro:
        "A release is a chain of small operations where one missed check can leave branches, tags, and version files out of sync. Bumpster turns that chain into one repeatable command.",
      cards: [
        {
          index: "01",
          title: "Checks before changes",
          text: "A clean worktree, valid version, expected branches, upstreams, remote refs, and the target tag are all verified before the first mutation.",
        },
        {
          index: "02",
          title: "One publication point",
          text: "Development, release, and tag refs are sent with one atomic push. If one ref is rejected, none of them move.",
        },
        {
          index: "03",
          title: "Small on purpose",
          text: "The installer downloads a checksummed runtime asset containing only the CLI files. No docs, tests, CI, or website source follows it home.",
        },
      ],
    },
    flow: {
      eyebrow: "RELEASE FLOW",
      title: "One command. Four deliberate stages.",
      steps: [
        {
          number: "01",
          title: "Preflight",
          text: "Inspect local state and fetch current refs from origin.",
          command: "git state → checked",
        },
        {
          number: "02",
          title: "Version",
          text: "Update `VERSION` and optionally the root `package.json` field.",
          command: "1.4.2 → 1.4.3",
        },
        {
          number: "03",
          title: "Prepare",
          text: "Create the version commit, fast-forward main, and annotate the tag.",
          command: "commit + tag",
        },
        {
          number: "04",
          title: "Publish",
          text: "Push dev, main, and the release tag together or not at all.",
          command: "git push --atomic",
        },
      ],
    },
    start: {
      eyebrow: "QUICK START",
      title: "From zero to the next release.",
      installTitle: "Install the latest stable release",
      pathTitle: "Add the command to PATH",
      releaseTitle: "Run a patch release",
      copy: "Copy",
      copied: "Copied",
      migration:
        "Using 0.8.x? Follow the one-time migration guide before running the old updater.",
      migrationLink: "Read migration guide",
    },
    commands: {
      eyebrow: "CLI REFERENCE",
      title: "A small command surface.",
      intro:
        "Use one action per invocation. Run without an option for an interactive major, minor, or patch prompt.",
      items: [
        ["-M", "--major", "Publish a major release"],
        ["-m", "--minor", "Publish a minor release"],
        ["-p", "--patch", "Publish a patch release"],
        ["-s", "--status", "Read repository status"],
        ["-f", "--create-feature", "Start a feature branch"],
        ["-c", "--close-feature", "Merge and close a feature"],
        ["-u", "--update", "Install the latest stable release"],
        ["-l", "--create-local-config", "Create project configuration"],
      ],
      contract: "Full CLI contract",
    },
    configure: {
      eyebrow: "FIT YOUR WORKFLOW",
      title: "Make Bumpster fit your workflow.",
      configTab: "Configuration",
      hooksTab: "Hooks",
      featureTab: "Branches",
      configTitle: "Project or global settings",
      configText:
        "Keep settings in `./.bumpsterrc` or `~/.bumpsterrc`. Project settings take priority.",
      hooksTitle: "Two clear extension points",
      hooksText:
        "Executable `pre-bump` and `post-bump` hooks receive the previous and next version as environment variables.",
      featureTitle: "Feature branches without git-flow",
      featureText:
        "Create a feature from the configured development branch, then merge, push, and optionally remove it through explicit commands.",
    },
    footprint: {
      eyebrow: "EASY TO REMOVE",
      title: "Small install. One-folder uninstall.",
      text: "Bumpster installs only its verified runtime and command wrappers under `~/.bumpster`. It is quick to put in place and just as easy to remove: delete that directory and the installed CLI is gone.",
      package: "~/.bumpster/",
      contents: "WHAT GETS INSTALLED",
      runtimeFiles: [
        ["bin/", "command wrappers"],
        ["bumpster.sh", "CLI entry point"],
        ["config.sh", "runtime defaults"],
        ["lib/", "required helpers"],
        ["VERSION", "installed version"],
        ["LICENSE", "MIT license"],
      ],
      noExtras: "No unrelated project files are installed.",
      uninstall: "REMOVE BUMPSTER",
    },
    closing: {
      eyebrow: "READY WHEN YOUR REPO IS",
      title: "Make the next version uneventful.",
      install: "Install Bumpster",
      source: "View source",
    },
    footer: {
      madeWith: "Made with",
      and: "and",
      madeBy: "and ❤️ by",
      author: "Pavel Tkachev",
      handle: "@phoenixweiss",
    },
  },
  ru: {
    skip: "Перейти к содержанию",
    nav: {
      why: "Почему Bumpster",
      flow: "Процесс релиза",
      commands: "Команды",
      github: "GitHub",
      language: "English",
      languageLabel: "Открыть английскую версию",
    },
    hero: {
      eyebrow: "СЕМАНТИЧЕСКИЕ ВЕРСИИ · GIT-РЕЛИЗЫ · BASH",
      title: ["Выпускайте версии", "легко"],
      lead: "Bumpster проверяет состояние Git, обновляет версию, создаёт тег и публикует все refs релиза одним защищённым процессом.",
      install: "Установить Bumpster",
      explore: "Посмотреть процесс",
      note: "Linux · macOS · Git Bash",
    },
    terminal: {
      label: "release.sh",
      select: "Выберите тип релиза",
      prompt: "$",
    },
    facts: [
      ["СРЕДА", "Bash + Git"],
      ["БЕЗОПАСНОСТЬ", "Атомарный Git push"],
      ["УСТАНОВКА", "Проверенный Release asset"],
      ["ЛИЦЕНЗИЯ", "MIT"],
    ],
    why: {
      eyebrow: "ПОЧЕМУ BUMPSTER",
      title: "Рутинная часть релиза должна оставаться рутинной.",
      intro:
        "Релиз — цепочка небольших операций, где одна пропущенная проверка оставляет ветки, теги и файлы версий рассинхронизированными. Bumpster превращает эту цепочку в одну повторяемую команду.",
      cards: [
        {
          index: "01",
          title: "Сначала проверки",
          text: "Чистое рабочее дерево, корректная версия, нужные ветки, upstream, remote refs и целевой тег проверяются до первого изменения.",
        },
        {
          index: "02",
          title: "Одна точка публикации",
          text: "Ветки разработки и релиза вместе с тегом отправляются атомарным push. Если один ref отклонён, не изменится ни один.",
        },
        {
          index: "03",
          title: "Ничего лишнего",
          text: "Installer скачивает runtime asset с checksum, содержащий только файлы CLI. Документация, тесты, CI и сайт на машину не попадут.",
        },
      ],
    },
    flow: {
      eyebrow: "ПРОЦЕСС РЕЛИЗА",
      title: "Одна команда. Четыре понятных этапа.",
      steps: [
        {
          number: "01",
          title: "Проверка",
          text: "Проверить локальное состояние и получить актуальные refs из origin.",
          command: "состояние Git → проверено",
        },
        {
          number: "02",
          title: "Версия",
          text: "Обновить `VERSION` и при необходимости корневое поле `package.json`.",
          command: "1.4.2 → 1.4.3",
        },
        {
          number: "03",
          title: "Подготовка",
          text: "Создать коммит версии, обновить main и добавить аннотированный тег.",
          command: "коммит + тег",
        },
        {
          number: "04",
          title: "Публикация",
          text: "Отправить dev, main и тег релиза вместе либо не отправлять ничего.",
          command: "git push --atomic",
        },
      ],
    },
    start: {
      eyebrow: "БЫСТРЫЙ СТАРТ",
      title: "От установки до следующего релиза.",
      installTitle: "Установите последний стабильный релиз",
      pathTitle: "Добавьте команду в PATH",
      releaseTitle: "Запустите patch-релиз",
      copy: "Копировать",
      copied: "Скопировано",
      migration:
        "Используете 0.8.x? Сначала выполните одноразовый переход и не запускайте старый updater.",
      migrationLink: "Инструкция по переходу",
    },
    commands: {
      eyebrow: "СПРАВОЧНИК CLI",
      title: "Небольшой набор команд.",
      intro:
        "Используйте одно действие за запуск. Без опций откроется интерактивный выбор major, minor или patch.",
      items: [
        ["-M", "--major", "Опубликовать major-релиз"],
        ["-m", "--minor", "Опубликовать minor-релиз"],
        ["-p", "--patch", "Опубликовать patch-релиз"],
        ["-s", "--status", "Показать состояние репозитория"],
        ["-f", "--create-feature", "Начать feature-ветку"],
        ["-c", "--close-feature", "Влить и закрыть feature-ветку"],
        ["-u", "--update", "Установить последний стабильный релиз"],
        ["-l", "--create-local-config", "Создать конфигурацию проекта"],
      ],
      contract: "Полный контракт CLI",
    },
    configure: {
      eyebrow: "ПОД ВАШ ПРОЦЕСС",
      title: "Настройте Bumpster под свой процесс.",
      configTab: "Конфигурация",
      hooksTab: "Хуки",
      featureTab: "Ветки",
      configTitle: "Настройки проекта или пользователя",
      configText:
        "Храните настройки в `./.bumpsterrc` или `~/.bumpsterrc`. Настройки проекта имеют приоритет.",
      hooksTitle: "Две понятные точки расширения",
      hooksText:
        "Исполняемые хуки `pre-bump` и `post-bump` получают предыдущую и новую версии через переменные окружения.",
      featureTitle: "Feature-ветки без git-flow",
      featureText:
        "Создайте feature-ветку от настроенной ветки разработки, затем влейте, отправьте и при необходимости удалите её явными командами.",
    },
    footprint: {
      eyebrow: "ЛЕГКО УДАЛИТЬ",
      title: "Компактная установка. Удаление одной папкой.",
      text: "Bumpster устанавливает только проверенный runtime и command wrappers в `~/.bumpster`. Поставить его просто, а удалить ещё проще: удалите эту директорию — и установленной CLI больше нет.",
      package: "~/.bumpster/",
      contents: "ЧТО УСТАНАВЛИВАЕТСЯ",
      runtimeFiles: [
        ["bin/", "command wrappers"],
        ["bumpster.sh", "точка входа CLI"],
        ["config.sh", "настройки runtime"],
        ["lib/", "необходимые функции"],
        ["VERSION", "установленная версия"],
        ["LICENSE", "лицензия MIT"],
      ],
      noExtras: "Посторонние файлы проекта не устанавливаются.",
      uninstall: "УДАЛИТЬ BUMPSTER",
    },
    closing: {
      eyebrow: "ГОТОВ, КОГДА ГОТОВ РЕПОЗИТОРИЙ",
      title: "Пусть следующая версия пройдёт без сюрпризов.",
      install: "Установить Bumpster",
      source: "Открыть исходники",
    },
    footer: {
      madeWith: "Сделано с помощью",
      and: "и",
      madeBy: "и с ❤️ от",
      author: "Павла Ткачева",
      handle: "@phoenixweiss",
    },
  },
};
