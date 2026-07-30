import { launch } from "chrome-launcher";
import lighthouse from "lighthouse";
import { preview } from "vite";

const categoryBudgets = {
  accessibility: 1,
  "best-practices": 0.95,
  performance: 0.9,
  seo: 1,
};

const metricBudgets = {
  "cumulative-layout-shift": 0.1,
  "largest-contentful-paint": 2500,
  "total-blocking-time": 200,
};

const resourceBudgets = {
  font: 260_000,
  script: 100_000,
  stylesheet: 32_000,
  total: 400_000,
};

function fail(message) {
  throw new Error(message);
}

function assertAtLeast(actual, expected, label) {
  if (typeof actual !== "number" || actual < expected) {
    fail(`${label} must be at least ${expected}; received ${actual}.`);
  }
}

function assertAtMost(actual, expected, label) {
  if (typeof actual !== "number" || actual > expected) {
    fail(`${label} must be at most ${expected}; received ${actual}.`);
  }
}

async function closePreview(server) {
  await new Promise((resolve, reject) => {
    server.httpServer.close((error) => {
      if (error) reject(error);
      else resolve();
    });
  });
}

const previewServer = await preview({
  preview: {
    host: "127.0.0.1",
    port: 0,
    strictPort: false,
  },
});
const address = previewServer.httpServer.address();

if (!address || typeof address === "string") {
  await closePreview(previewServer);
  fail("Could not determine the Vite preview port.");
}

let chrome;

try {
  chrome = await launch({
    chromeFlags: ["--headless=new", "--no-sandbox"],
    chromePath: process.env.CHROME_PATH,
  });

  for (const path of ["/Bumpster/", "/Bumpster/ru/"]) {
    const url = `http://127.0.0.1:${address.port}${path}`;
    const result = await lighthouse(url, {
      logLevel: "error",
      onlyCategories: Object.keys(categoryBudgets),
      output: "json",
      port: chrome.port,
    });

    if (!result?.lhr) fail(`Lighthouse did not return a report for ${url}.`);

    const { audits, categories } = result.lhr;
    const scores = {};

    for (const [category, minimumScore] of Object.entries(categoryBudgets)) {
      const score = categories[category]?.score;
      scores[category] = score;

      if (typeof score === "number" && score < minimumScore) {
        const failedAudits = categories[category].auditRefs
          .filter(({ id, weight }) => weight > 0 && audits[id]?.score !== 1)
          .flatMap(({ id }) => {
            const audit = audits[id];
            const failingNodes = (audit.details?.items ?? [])
              .map((item) => item.node?.selector)
              .filter(Boolean)
              .slice(0, 10);

            return [
              `${id}: ${audit.title}`,
              ...failingNodes.map((selector) => `  ${selector}`),
            ];
          });

        console.error(
          `${path} ${category} audits below budget:\n${failedAudits.join("\n")}`,
        );
      }

      assertAtLeast(score, minimumScore, `${path} ${category} score`);
    }

    for (const [audit, maximumValue] of Object.entries(metricBudgets)) {
      assertAtMost(
        audits[audit]?.numericValue,
        maximumValue,
        `${path} ${audit}`,
      );
    }

    const resourceSummary = audits["resource-summary"]?.details?.items;
    if (!Array.isArray(resourceSummary)) {
      fail(`Lighthouse did not return a resource summary for ${url}.`);
    }

    for (const [resourceType, maximumSize] of Object.entries(resourceBudgets)) {
      const resource = resourceSummary.find(
        (item) => item.resourceType === resourceType,
      );
      assertAtMost(
        resource?.transferSize ?? 0,
        maximumSize,
        `${path} ${resourceType} transfer size`,
      );
    }

    console.log(
      `${path} Lighthouse scores: ${Object.entries(scores)
        .map(([category, score]) => `${category}=${Math.round(score * 100)}`)
        .join(", ")}`,
    );
  }
} finally {
  if (chrome) await chrome.kill();
  await closePreview(previewServer);
}

console.log("Lighthouse budgets passed.");
