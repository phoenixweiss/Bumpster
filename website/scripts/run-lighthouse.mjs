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

const numberOfRuns = 3;

function fail(message) {
  throw new Error(message);
}

function median(values, label) {
  if (values.some((value) => typeof value !== "number")) {
    fail(`${label} did not return a numeric value in every run.`);
  }

  const sortedValues = [...values].sort((left, right) => left - right);
  return sortedValues[Math.floor(sortedValues.length / 2)];
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

function resourceSize(report, resourceType, url) {
  const resourceSummary = report.audits["resource-summary"]?.details?.items;
  if (!Array.isArray(resourceSummary)) {
    fail(`Lighthouse did not return a resource summary for ${url}.`);
  }

  return (
    resourceSummary.find((item) => item.resourceType === resourceType)
      ?.transferSize ?? 0
  );
}

function printCategoryFailures(path, category, report) {
  const { audits, categories } = report;
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
    const reports = [];

    for (let run = 1; run <= numberOfRuns; run += 1) {
      const result = await lighthouse(url, {
        logLevel: "error",
        onlyCategories: Object.keys(categoryBudgets),
        output: "json",
        port: chrome.port,
      });

      if (!result?.lhr) fail(`Lighthouse did not return a report for ${url}.`);

      reports.push(result.lhr);

      const runScores = Object.fromEntries(
        Object.keys(categoryBudgets).map((category) => [
          category,
          result.lhr.categories[category]?.score,
        ]),
      );
      const runMetrics = Object.fromEntries(
        Object.keys(metricBudgets).map((audit) => [
          audit,
          result.lhr.audits[audit]?.numericValue,
        ]),
      );

      console.log(
        `${path} Lighthouse run ${run}/${numberOfRuns}: ` +
          `${Object.entries(runScores)
            .map(([category, score]) =>
              typeof score === "number"
                ? `${category}=${Math.round(score * 100)}`
                : `${category}=missing`,
            )
            .join(", ")}; ` +
          `CLS=${runMetrics["cumulative-layout-shift"]?.toFixed(3) ?? "missing"}, ` +
          `LCP=${Math.round(runMetrics["largest-contentful-paint"] ?? 0)}ms, ` +
          `TBT=${Math.round(runMetrics["total-blocking-time"] ?? 0)}ms`,
      );
    }

    const scores = {};

    for (const [category, minimumScore] of Object.entries(categoryBudgets)) {
      const score = median(
        reports.map((report) => report.categories[category]?.score),
        `${path} ${category} score`,
      );
      scores[category] = score;

      if (score < minimumScore) {
        const lowestReport = reports.reduce((lowest, report) =>
          report.categories[category].score < lowest.categories[category].score
            ? report
            : lowest,
        );
        printCategoryFailures(path, category, lowestReport);
      }

      assertAtLeast(score, minimumScore, `${path} ${category} score`);
    }

    for (const [audit, maximumValue] of Object.entries(metricBudgets)) {
      const metric = median(
        reports.map((report) => report.audits[audit]?.numericValue),
        `${path} ${audit}`,
      );
      assertAtMost(metric, maximumValue, `${path} ${audit}`);
    }

    for (const [resourceType, maximumSize] of Object.entries(resourceBudgets)) {
      const maximumTransferSize = Math.max(
        ...reports.map((report) => resourceSize(report, resourceType, url)),
      );
      assertAtMost(
        maximumTransferSize,
        maximumSize,
        `${path} ${resourceType} transfer size`,
      );
    }

    console.log(
      `${path} Lighthouse scores: ${Object.entries(scores)
        .map(([category, score]) => `${category}=${Math.round(score * 100)}`)
        .join(", ")} (median of ${numberOfRuns})`,
    );
  }
} finally {
  if (chrome) await chrome.kill();
  await closePreview(previewServer);
}

console.log("Lighthouse budgets passed.");
