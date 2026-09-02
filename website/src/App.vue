<script setup>
import { computed, ref } from "vue";

import brandLockupUrl from "@/assets/bumpster-lockup.svg";
import { content } from "@/data/content";
import {
  bumpOptions,
  configExample,
  createTerminalLines,
  featureExample,
  hotfixExample,
  homebrewInstallCommand,
  homebrewUninstallCommand,
  homebrewUpdateCommand,
  hooksExample,
  pathCommand,
  standaloneInstallCommand,
  standaloneUninstallCommand,
} from "@/data/examples";

const props = defineProps({
  locale: {
    type: String,
    default: "en",
  },
});

const releaseType = ref("patch");
const copiedKey = ref("");
const activeGuide = ref("config");
const installMethod = ref("homebrew");

const t = computed(() => content[props.locale] ?? content.en);
const release = computed(() => bumpOptions[releaseType.value]);
const terminalLines = computed(() =>
  createTerminalLines(release.value, releaseType.value),
);
const currentYear = new Date().getFullYear();
const baseUrl = import.meta.env.BASE_URL;
const bumpsterVersion = import.meta.env.BUMPSTER_VERSION;
const releaseUrl = `https://github.com/phoenixweiss/Bumpster/releases/tag/v${bumpsterVersion}`;
const languageUrl = computed(() =>
  props.locale === "ru" ? baseUrl : `${baseUrl}ru/`,
);
const readmeUrl = computed(() =>
  props.locale === "ru"
    ? "https://github.com/phoenixweiss/Bumpster/blob/main/README_RU.md"
    : "https://github.com/phoenixweiss/Bumpster/blob/main/README.md",
);
const contractUrl = computed(() =>
  props.locale === "ru"
    ? "https://github.com/phoenixweiss/Bumpster/blob/main/docs/CLI_CONTRACT_RU.md"
    : "https://github.com/phoenixweiss/Bumpster/blob/main/docs/CLI_CONTRACT.md",
);

const installation = computed(() => {
  if (installMethod.value === "standalone") {
    return {
      installTitle: t.value.start.standaloneInstallTitle,
      secondTitle: t.value.start.standaloneSecondTitle,
      installCommand: standaloneInstallCommand,
      secondCommand: pathCommand,
      packageLabel: t.value.footprint.packageStandalone,
      uninstallCommand: standaloneUninstallCommand,
    };
  }

  return {
    installTitle: t.value.start.homebrewInstallTitle,
    secondTitle: t.value.start.homebrewSecondTitle,
    installCommand: homebrewInstallCommand,
    secondCommand: homebrewUpdateCommand,
    packageLabel: t.value.footprint.packageHomebrew,
    uninstallCommand: homebrewUninstallCommand,
  };
});

const guide = computed(() => {
  const guides = {
    config: {
      title: t.value.configure.configTitle,
      text: t.value.configure.configText,
      code: configExample,
    },
    hooks: {
      title: t.value.configure.hooksTitle,
      text: t.value.configure.hooksText,
      code: hooksExample,
    },
    features: {
      title: t.value.configure.featureTitle,
      text: t.value.configure.featureText,
      code: featureExample,
    },
    hotfix: {
      title: t.value.configure.hotfixTitle,
      text: t.value.configure.hotfixText,
      code: hotfixExample,
    },
  };

  return guides[activeGuide.value];
});

function inlineCodeParts(text) {
  return text
    .split(/(`[^`]+`)/g)
    .filter(Boolean)
    .map((part) => ({
      code: part.startsWith("`") && part.endsWith("`"),
      text:
        part.startsWith("`") && part.endsWith("`") ? part.slice(1, -1) : part,
    }));
}

async function copyText(key, value) {
  try {
    await navigator.clipboard.writeText(value);
    copiedKey.value = key;
    window.setTimeout(() => {
      if (copiedKey.value === key) copiedKey.value = "";
    }, 1800);
  } catch {
    copiedKey.value = "";
  }
}
</script>

<template>
  <a class="skip-link" href="#main">{{ t.skip }}</a>

  <header class="site-header">
    <div class="shell header-inner">
      <a class="brand" :href="baseUrl" aria-label="Bumpster home">
        <img
          class="brand-lockup"
          :src="brandLockupUrl"
          alt=""
          aria-hidden="true"
        />
      </a>

      <nav
        class="primary-nav"
        :aria-label="
          props.locale === 'ru' ? 'Основная навигация' : 'Primary navigation'
        "
      >
        <a href="#why">{{ t.nav.why }}</a>
        <a href="#flow">{{ t.nav.flow }}</a>
        <a href="#commands">{{ t.nav.commands }}</a>
      </nav>

      <div class="header-actions">
        <a
          class="language-link"
          :href="languageUrl"
          :aria-label="t.nav.languageLabel"
          >{{ t.nav.language }}</a
        >
        <a
          class="github-link"
          href="https://github.com/phoenixweiss/Bumpster"
          target="_blank"
          rel="noreferrer"
        >
          {{ t.nav.github }}
          <span aria-hidden="true">↗</span>
        </a>
      </div>
    </div>
  </header>

  <main id="main">
    <section class="hero">
      <div class="hero-grid" aria-hidden="true"></div>
      <div class="shell hero-inner">
        <div class="hero-copy">
          <p class="eyebrow">{{ t.hero.eyebrow }}</p>
          <h1>
            {{ t.hero.title[0] }}
            <span>{{ t.hero.title[1] }}</span>
          </h1>
          <p class="hero-lead">{{ t.hero.lead }}</p>
          <div class="hero-actions">
            <a class="button button-primary" href="#start">
              {{ t.hero.install }}
              <span aria-hidden="true">↓</span>
            </a>
            <a class="button button-quiet" href="#commands">
              {{ t.hero.explore }}
              <span aria-hidden="true">↓</span>
            </a>
          </div>
          <p class="platform-note">
            <span aria-hidden="true"></span>
            {{ t.hero.note }}
          </p>
        </div>

        <div class="terminal-wrap">
          <div class="release-switcher">
            <span>{{ t.terminal.select }}</span>
            <div role="group" :aria-label="t.terminal.select">
              <button
                v-for="type in ['patch', 'minor', 'major', 'hotfix']"
                :key="type"
                type="button"
                :class="{ active: releaseType === type }"
                :aria-pressed="releaseType === type"
                @click="releaseType = type"
              >
                {{ type }}
              </button>
            </div>
          </div>

          <div class="terminal" aria-live="polite">
            <div class="terminal-bar">
              <div class="terminal-dots" aria-hidden="true">
                <span></span><span></span><span></span>
              </div>
              <span>{{ t.terminal.label }}</span>
              <span>80×24</span>
            </div>
            <div class="terminal-body">
              <div class="terminal-command">
                <span>{{ t.terminal.prompt }}</span>
                <strong>
                  bumpster
                  <span class="terminal-variable">--{{ releaseType }}</span>
                </strong>
              </div>
              <div class="terminal-output">
                <p v-for="line in terminalLines" :key="line.id">
                  <span class="log-level">[INFO]</span>
                  <span>
                    <span
                      v-for="(segment, index) in line.segments"
                      :key="index"
                      :class="{ 'terminal-variable': segment.variable }"
                      >{{ segment.text }}</span
                    >
                  </span>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="facts" aria-label="Bumpster facts">
      <div class="shell facts-grid">
        <div v-for="fact in t.facts" :key="fact[0]" class="fact">
          <span>{{ fact[0] }}</span>
          <strong>{{ fact[1] }}</strong>
        </div>
      </div>
    </section>

    <section id="why" class="section why-section">
      <div class="shell">
        <div class="section-heading split-heading">
          <div>
            <p class="eyebrow">{{ t.why.eyebrow }}</p>
            <h2>{{ t.why.title }}</h2>
          </div>
          <p>{{ t.why.intro }}</p>
        </div>

        <div class="why-grid">
          <article
            v-for="card in t.why.cards"
            :key="card.index"
            class="why-card"
          >
            <div class="card-symbol" aria-hidden="true">
              <span v-if="card.index === '01'">?</span>
              <span v-else-if="card.index === '02'">↯</span>
              <span v-else>·/</span>
            </div>
            <h3>{{ card.title }}</h3>
            <p>{{ card.text }}</p>
          </article>
        </div>
      </div>
    </section>

    <section id="flow" class="section flow-section">
      <div class="shell">
        <div class="section-heading">
          <p class="eyebrow">{{ t.flow.eyebrow }}</p>
          <h2>{{ t.flow.title }}</h2>
        </div>

        <div class="flow-list">
          <article
            v-for="step in t.flow.steps"
            :key="step.number"
            class="flow-step"
          >
            <span class="step-number">{{ step.number }}</span>
            <div>
              <h3>{{ step.title }}</h3>
              <p>
                <template
                  v-for="(part, index) in inlineCodeParts(step.text)"
                  :key="index"
                >
                  <code v-if="part.code" class="inline-code">{{
                    part.text
                  }}</code>
                  <span v-else>{{ part.text }}</span>
                </template>
              </p>
            </div>
            <code>{{ step.command }}</code>
          </article>
        </div>
      </div>
    </section>

    <section id="start" class="section start-section">
      <div class="shell">
        <div class="section-heading split-heading start-heading">
          <div>
            <p class="eyebrow">{{ t.start.eyebrow }}</p>
            <h2>{{ t.start.title }}</h2>
          </div>
          <div
            class="guide-tabs install-tabs"
            role="tablist"
            :aria-label="t.start.methodLabel"
          >
            <button
              id="homebrew-install-tab"
              type="button"
              role="tab"
              :aria-selected="installMethod === 'homebrew'"
              aria-controls="install-panel"
              :class="{ active: installMethod === 'homebrew' }"
              @click="installMethod = 'homebrew'"
            >
              {{ t.start.homebrewTab }}
            </button>
            <button
              id="standalone-install-tab"
              type="button"
              role="tab"
              :aria-selected="installMethod === 'standalone'"
              aria-controls="install-panel"
              :class="{ active: installMethod === 'standalone' }"
              @click="installMethod = 'standalone'"
            >
              {{ t.start.standaloneTab }}
            </button>
          </div>
        </div>

        <div
          id="install-panel"
          class="command-stack"
          role="tabpanel"
          :aria-labelledby="`${installMethod}-install-tab`"
        >
          <article class="command-block">
            <div>
              <span>01</span>
              <h3>{{ installation.installTitle }}</h3>
            </div>
            <div class="code-row">
              <code>{{ installation.installCommand }}</code>
              <button
                type="button"
                @click="copyText('install', installation.installCommand)"
              >
                {{ copiedKey === "install" ? t.start.copied : t.start.copy }}
              </button>
            </div>
          </article>
          <article class="command-block">
            <div>
              <span>02</span>
              <h3>{{ installation.secondTitle }}</h3>
            </div>
            <div class="code-row">
              <code>{{ installation.secondCommand }}</code>
              <button
                type="button"
                @click="copyText('path', installation.secondCommand)"
              >
                {{ copiedKey === "path" ? t.start.copied : t.start.copy }}
              </button>
            </div>
          </article>
          <article class="command-block">
            <div>
              <span>03</span>
              <h3>{{ t.start.releaseTitle }}</h3>
            </div>
            <div class="code-row">
              <code>bumpster --patch</code>
              <button
                type="button"
                @click="copyText('release', 'bumpster --patch')"
              >
                {{ copiedKey === "release" ? t.start.copied : t.start.copy }}
              </button>
            </div>
          </article>
        </div>

        <aside class="migration-note install-note">
          <span aria-hidden="true">{{
            installMethod === "homebrew" ? "i" : "!"
          }}</span>
          <p v-if="installMethod === 'homebrew'">
            <template
              v-for="(part, index) in inlineCodeParts(t.start.homebrewNote)"
              :key="index"
            >
              <code v-if="part.code" class="inline-code">{{ part.text }}</code>
              <span v-else>{{ part.text }}</span>
            </template>
          </p>
          <p v-else>
            {{ t.start.migration }}
            <a
              :href="`${readmeUrl}#${props.locale === 'ru' ? 'переход-с-08x' : 'migrating-from-08x'}`"
            >
              {{ t.start.migrationLink }} <span aria-hidden="true">↗</span>
            </a>
          </p>
        </aside>
      </div>
    </section>

    <section id="commands" class="section commands-section">
      <div class="shell commands-layout">
        <div class="commands-copy">
          <p class="eyebrow">{{ t.commands.eyebrow }}</p>
          <h2>{{ t.commands.title }}</h2>
          <p>{{ t.commands.intro }}</p>
          <a :href="contractUrl" target="_blank" rel="noreferrer">
            {{ t.commands.contract }} <span aria-hidden="true">↗</span>
          </a>
        </div>

        <div class="command-table">
          <div
            v-for="item in t.commands.items"
            :key="item[1]"
            class="command-item"
          >
            <kbd>{{ item[0] }}</kbd>
            <code>{{ item[1] }}</code>
            <span>{{ item[2] }}</span>
          </div>
        </div>
      </div>
    </section>

    <section class="section configure-section">
      <div class="shell">
        <div class="section-heading split-heading">
          <div>
            <p class="eyebrow">{{ t.configure.eyebrow }}</p>
            <h2>{{ t.configure.title }}</h2>
          </div>
          <div class="guide-tabs configure-tabs" role="tablist">
            <button
              id="config-tab"
              type="button"
              role="tab"
              :aria-selected="activeGuide === 'config'"
              aria-controls="guide-panel"
              :class="{ active: activeGuide === 'config' }"
              @click="activeGuide = 'config'"
            >
              {{ t.configure.configTab }}
            </button>
            <button
              id="hooks-tab"
              type="button"
              role="tab"
              :aria-selected="activeGuide === 'hooks'"
              aria-controls="guide-panel"
              :class="{ active: activeGuide === 'hooks' }"
              @click="activeGuide = 'hooks'"
            >
              {{ t.configure.hooksTab }}
            </button>
            <button
              id="features-tab"
              type="button"
              role="tab"
              :aria-selected="activeGuide === 'features'"
              aria-controls="guide-panel"
              :class="{ active: activeGuide === 'features' }"
              @click="activeGuide = 'features'"
            >
              {{ t.configure.featureTab }}
            </button>
            <button
              id="hotfix-tab"
              type="button"
              role="tab"
              :aria-selected="activeGuide === 'hotfix'"
              aria-controls="guide-panel"
              :class="{ active: activeGuide === 'hotfix' }"
              @click="activeGuide = 'hotfix'"
            >
              {{ t.configure.hotfixTab }}
            </button>
          </div>
        </div>

        <div
          id="guide-panel"
          class="guide-panel"
          role="tabpanel"
          :aria-labelledby="`${activeGuide}-tab`"
        >
          <div class="guide-copy">
            <h3>{{ guide.title }}</h3>
            <p>
              <template
                v-for="(part, index) in inlineCodeParts(guide.text)"
                :key="index"
              >
                <code v-if="part.code" class="inline-code">{{
                  part.text
                }}</code>
                <span v-else>{{ part.text }}</span>
              </template>
            </p>
          </div>
          <pre><code>{{ guide.code }}</code></pre>
        </div>
      </div>
    </section>

    <section class="section footprint-section">
      <div class="shell footprint-layout">
        <div class="footprint-copy">
          <p class="eyebrow">{{ t.footprint.eyebrow }}</p>
          <h2>{{ t.footprint.title }}</h2>
          <p>
            <template
              v-for="(part, index) in inlineCodeParts(t.footprint.text)"
              :key="index"
            >
              <code v-if="part.code" class="inline-code">{{ part.text }}</code>
              <span v-else>{{ part.text }}</span>
            </template>
          </p>
          <div
            class="guide-tabs install-tabs footprint-tabs"
            role="tablist"
            :aria-label="t.start.methodLabel"
          >
            <button
              id="homebrew-footprint-tab"
              type="button"
              role="tab"
              :aria-selected="installMethod === 'homebrew'"
              aria-controls="footprint-panel"
              :class="{ active: installMethod === 'homebrew' }"
              @click="installMethod = 'homebrew'"
            >
              {{ t.start.homebrewTab }}
            </button>
            <button
              id="standalone-footprint-tab"
              type="button"
              role="tab"
              :aria-selected="installMethod === 'standalone'"
              aria-controls="footprint-panel"
              :class="{ active: installMethod === 'standalone' }"
              @click="installMethod = 'standalone'"
            >
              {{ t.start.standaloneTab }}
            </button>
          </div>
        </div>

        <div
          id="footprint-panel"
          class="package-card"
          role="tabpanel"
          :aria-labelledby="`${installMethod}-footprint-tab`"
        >
          <div class="package-title">
            <span aria-hidden="true">▣</span>
            <strong>{{ installation.packageLabel }}</strong>
          </div>
          <div class="runtime-tree">
            <span class="package-label">{{ t.footprint.contents }}</span>
            <div
              v-for="file in t.footprint.runtimeFiles"
              :key="file[0]"
              class="runtime-file"
            >
              <code><span aria-hidden="true">├─</span> {{ file[0] }}</code>
              <span>{{ file[1] }}</span>
            </div>
            <p>{{ t.footprint.noExtras }}</p>
          </div>
          <div class="uninstall-row">
            <div>
              <span>{{ t.footprint.uninstall }}</span>
              <code>{{ installation.uninstallCommand }}</code>
            </div>
            <button
              type="button"
              @click="copyText('uninstall', installation.uninstallCommand)"
            >
              {{ copiedKey === "uninstall" ? t.start.copied : t.start.copy }}
            </button>
          </div>
        </div>
      </div>
    </section>

    <section class="closing-section">
      <div class="closing-grid" aria-hidden="true"></div>
      <div class="shell closing-inner">
        <div class="closing-brand">
          <img class="brand-lockup" :src="brandLockupUrl" alt="Bumpster" />
        </div>
        <p class="eyebrow">{{ t.closing.eyebrow }}</p>
        <h2>{{ t.closing.title }}</h2>
        <div class="closing-actions">
          <a class="button button-light" href="#start">
            {{ t.closing.install }}
            <span aria-hidden="true">↑</span>
          </a>
          <a
            class="button button-outline"
            href="https://github.com/phoenixweiss/Bumpster"
            target="_blank"
            rel="noreferrer"
          >
            {{ t.closing.source }} <span aria-hidden="true">↗</span>
          </a>
        </div>
      </div>
    </section>
  </main>

  <footer class="site-footer">
    <div class="shell footer-inner">
      <small class="footer-version">
        <a
          :href="releaseUrl"
          :aria-label="`${t.footer.versionLabel} ${bumpsterVersion}`"
          target="_blank"
          rel="noreferrer"
        >
          Bumpster v{{ bumpsterVersion }}
        </a>
      </small>
      <small>
        &copy; {{ currentYear }} {{ t.footer.madeWith }}
        <a href="https://vuejs.org/" target="_blank" rel="noreferrer">Vue</a>
        {{ t.footer.and }}
        <a href="https://vite.dev/" target="_blank" rel="noreferrer">Vite</a>,
        {{ t.footer.madeBy }}
        <a href="https://phoenixweiss.me" target="_blank" rel="noreferrer">
          {{ t.footer.author }}
          <em>({{ t.footer.handle }})</em>
        </a>
      </small>
    </div>
  </footer>
</template>
