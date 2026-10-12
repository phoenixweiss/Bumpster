import { readFileSync } from "node:fs";
import { fileURLToPath, URL } from "node:url";

import vue from "@vitejs/plugin-vue";
import { defineConfig } from "vite";

const bumpsterVersion = readFileSync(
  fileURLToPath(new URL("../VERSION", import.meta.url)),
  "utf8",
).trim();

if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(bumpsterVersion)) {
  throw new Error("Root VERSION must contain MAJOR.MINOR.PATCH.");
}

const websiteVersion = readFileSync(
  fileURLToPath(new URL("./VERSION", import.meta.url)),
  "utf8",
).trim();
const manifest = JSON.parse(
  readFileSync(
    fileURLToPath(new URL("./package.json", import.meta.url)),
    "utf8",
  ),
);

if (
  !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(websiteVersion) ||
  manifest.version !== websiteVersion
) {
  throw new Error(
    "Website VERSION must match the package.json semantic version.",
  );
}

export default defineConfig({
  base: "/Bumpster/",
  define: {
    "import.meta.env.BUMPSTER_VERSION": JSON.stringify(bumpsterVersion),
  },
  plugins: [
    vue(),
    {
      name: "release-versions",
      generateBundle() {
        this.emitFile({
          type: "asset",
          fileName: "version.json",
          source:
            JSON.stringify({ cli: bumpsterVersion, website: websiteVersion }) +
            "\n",
        });
      },
    },
  ],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  build: {
    rollupOptions: {
      input: {
        main: fileURLToPath(new URL("./index.html", import.meta.url)),
        ru: fileURLToPath(new URL("./ru/index.html", import.meta.url)),
      },
    },
  },
});
