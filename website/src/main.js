import { createApp } from "vue";

import "@fontsource-variable/nunito-sans";
import "@fontsource/ibm-plex-mono/cyrillic-400.css";
import "@fontsource/ibm-plex-mono/cyrillic-700.css";
import "@fontsource/ibm-plex-mono/latin-400.css";
import "@fontsource/ibm-plex-mono/latin-700.css";
import App from "./App.vue";
import "./assets/main.css";

createApp(App, {
  locale: document.documentElement.lang === "ru" ? "ru" : "en",
}).mount("#app");
