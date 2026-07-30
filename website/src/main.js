import { createApp } from "vue";

import "@fontsource-variable/nunito-sans";
import "@fontsource/space-mono/400.css";
import "@fontsource/space-mono/700.css";
import App from "./App.vue";
import "./assets/main.css";

createApp(App, {
  locale: document.documentElement.lang === "ru" ? "ru" : "en",
}).mount("#app");
