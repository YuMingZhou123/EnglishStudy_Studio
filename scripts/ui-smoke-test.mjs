import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import net from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";

const text = {
  beginnerDictation: "\u521d\u7ea7\u8bed\u5883\u542c\u5199",
  advancedDictation: "\u9ad8\u7ea7\u8bed\u5883\u542c\u5199",
  normalSpeed: "\u539f\u901f\u6717\u8bfb",
  slowSpeed: "\u6162\u901f\u6717\u8bfb",
  firstLetter: "\u9996\u5b57\u6bcd",
  meaningHint: "\u4e2d\u6587\u63d0\u793a",
  submitAnswer: "\u63d0\u4ea4\u7b54\u6848",
  scoreUnit: "\u5206",
  dashboard: "\u7ee7\u7eed\u4eca\u5929\u7684\u8bed\u5883\u542c\u5199",
  vocabulary: "\u6211\u7684\u590d\u4e60",
  startReview: "\u5f00\u59cb\u590d\u4e60",
  reports: "\u5b66\u4e60\u8bb0\u5f55",
  reportDetails: "\u7ec3\u4e60\u660e\u7ec6",
  adminTitle: "\u5185\u5bb9\u7ba1\u7406",
  newSentence: "\u65b0\u589e\u53e5\u5b50",
  batchImport: "\u6279\u91cf\u5bfc\u5165",
};

const baseUrl = process.env.WEB_BASE_URL ?? "http://localhost:3000";
const browserPath = findBrowserPath();
const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

if (typeof WebSocket !== "function") {
  throw new Error("Node.js global WebSocket is required. Use Node.js 22+.");
}

function findBrowserPath() {
  const candidates = [
    process.env.BROWSER_PATH,
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/microsoft-edge",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ].filter(Boolean);

  const browser = candidates.find((candidate) => existsSync(candidate));
  if (!browser) {
    throw new Error("Could not find Edge or Chrome. Set BROWSER_PATH to run UI smoke tests.");
  }

  return browser;
}

async function getFreePort() {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = address.port;
      server.close(() => resolve(port));
    });
  });
}

async function waitFor(fn, label, timeoutMs = 15_000) {
  const started = Date.now();
  let lastError;

  while (Date.now() - started < timeoutMs) {
    try {
      const value = await fn();
      if (value) {
        return value;
      }
    } catch (error) {
      lastError = error;
    }

    await sleep(250);
  }

  throw new Error(`${label} timed out${lastError ? `: ${lastError.message}` : ""}`);
}

function waitForExit(process, timeoutMs = 5_000) {
  return new Promise((resolve) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        resolve(false);
      }
    }, timeoutMs);

    process.once("exit", () => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(true);
      }
    });
  });
}

function createCdpClient(ws) {
  let nextId = 1;
  const pending = new Map();

  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (!message.id) {
      return;
    }

    const handlers = pending.get(message.id);
    if (!handlers) {
      return;
    }

    pending.delete(message.id);
    if (message.error) {
      handlers.reject(new Error(message.error.message));
    } else {
      handlers.resolve(message.result);
    }
  });

  return function cdp(method, params = {}) {
    const id = nextId++;
    ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  };
}

async function main() {
  const port = await getFreePort();
  const profileDir = await mkdtemp(path.join(tmpdir(), "english-study-ui-smoke-"));
  const browser = spawn(
    browserPath,
    [
      "--headless=new",
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${profileDir}`,
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "about:blank",
    ],
    { stdio: "ignore", windowsHide: true },
  );

  let ws;
  let passed = false;

  try {
    await waitFor(async () => {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      return response.ok;
    }, "Browser DevTools startup");

    const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const page = targets.find((target) => target.type === "page");
    if (!page) {
      throw new Error("No page target found.");
    }

    ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      ws.addEventListener("open", resolve, { once: true });
      ws.addEventListener("error", reject, { once: true });
    });

    const cdp = createCdpClient(ws);

    async function evalJs(expression) {
      const result = await cdp("Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      });

      if (result.exceptionDetails) {
        throw new Error(
          result.exceptionDetails.exception?.description ??
            result.exceptionDetails.text ??
            "Runtime evaluation failed",
        );
      }

      return result.result.value;
    }

    async function navigate(pathOrUrl) {
      const url = pathOrUrl.startsWith("http") ? pathOrUrl : `${baseUrl}${pathOrUrl}`;
      await cdp("Page.navigate", { url });
      await waitFor(
        () => evalJs(`location.href.startsWith(${JSON.stringify(url)})`),
        `url ${url}`,
      );
      await waitFor(
        () =>
          evalJs(
            'document.readyState === "complete" || document.readyState === "interactive"',
          ),
        `load ${url}`,
      );
    }

    async function setViewport(width, height, mobile = false) {
      await cdp("Emulation.setDeviceMetricsOverride", {
        width,
        height,
        deviceScaleFactor: mobile ? 2 : 1,
        mobile,
      });
      await cdp("Emulation.setTouchEmulationEnabled", { enabled: mobile });
      await sleep(250);
    }

    async function assertNoHorizontalOverflow(label) {
      const result = await evalJs(`(() => {
        const documentElement = document.documentElement;
        const body = document.body;
        const viewportWidth = documentElement.clientWidth;
        const pageWidth = Math.max(
          documentElement.scrollWidth,
          body ? body.scrollWidth : 0,
        );
        const overflowing = [...document.querySelectorAll("body *")]
          .map((element) => {
            const rect = element.getBoundingClientRect();
            const tag = element.tagName.toLowerCase();
            const text = (element.innerText || element.value || "").trim().replace(/\\s+/g, " ");
            return {
              tag,
              text: text.slice(0, 80),
              left: Math.round(rect.left),
              right: Math.round(rect.right),
              width: Math.round(rect.width),
            };
          })
          .filter((item) => item.width > 0 && (item.left < -4 || item.right > viewportWidth + 4))
          .slice(0, 8);

        return {
          viewportWidth,
          pageWidth,
          overflowBy: pageWidth - viewportWidth,
          overflowing,
        };
      })()`);

      if (result.overflowBy > 4 || result.overflowing.length > 0) {
        throw new Error(
          `${label} has horizontal overflow: ${JSON.stringify(result)}`,
        );
      }
    }

    async function waitText(value, timeoutMs = 15_000) {
      await waitFor(
        () =>
          evalJs(
            `document.body && document.body.innerText.includes(${JSON.stringify(value)})`,
          ),
        `text ${JSON.stringify(value)}`,
        timeoutMs,
      );
    }

    async function waitTitle(value, timeoutMs = 15_000) {
      await waitFor(
        () => evalJs(`document.title === ${JSON.stringify(value)}`),
        `title ${JSON.stringify(value)}`,
        timeoutMs,
      );
    }

    async function waitPath(value, timeoutMs = 15_000) {
      await waitFor(
        () => evalJs(`location.pathname === ${JSON.stringify(value)}`),
        `path ${value}`,
        timeoutMs,
      );
    }

    async function clickText(value) {
      const clicked = await evalJs(`(() => {
        const wanted = ${JSON.stringify(value)};
        const elements = [...document.querySelectorAll("button,a")];
        const element = elements.find(
          (item) => item.innerText.trim().includes(wanted) && !item.disabled,
        );
        if (!element) return false;
        element.click();
        return true;
      })()`);

      if (!clicked) {
        throw new Error(`Could not click text: ${JSON.stringify(value)}`);
      }
    }

    async function submitLoginForm() {
      await sleep(2_000);
      const submitted = await evalJs(`(() => {
        const form = document.querySelector("form");
        if (!form) return false;
        form.requestSubmit();
        return true;
      })()`);

      if (!submitted) {
        throw new Error("Login form was not found.");
      }
    }

    async function fill(selector, value) {
      const ok = await evalJs(`(() => {
        const element = document.querySelector(${JSON.stringify(selector)});
        if (!element) return false;
        const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), "value");
        descriptor.set.call(element, ${JSON.stringify(value)});
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return true;
      })()`);

      if (!ok) {
        throw new Error(`Could not fill selector: ${selector}`);
      }
    }

    await cdp("Page.enable");
    await cdp("Runtime.enable");
    await setViewport(1365, 900, false);

    await navigate("/");
    await waitTitle("EnglishStudy Studio");
    await submitLoginForm();
    await waitPath("/dashboard");
    await waitText(text.dashboard);

    await navigate("/dictation?mode=beginner");
    await waitText(text.beginnerDictation);
    await waitFor(
      () =>
        evalJs(
          'document.querySelectorAll("input[aria-label=\\"blank answer\\"]").length > 0',
        ),
      "blank inputs",
    );
    await clickText(text.normalSpeed);
    await clickText(text.slowSpeed);
    await clickText(text.firstLetter);
    await clickText(text.meaningHint);
    await evalJs(`(() => {
      document.querySelectorAll('input[aria-label="blank answer"]').forEach((element) => {
        const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), "value");
        descriptor.set.call(element, "x");
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
      });
      return true;
    })()`);
    await clickText(text.submitAnswer);
    await waitText(text.scoreUnit);

    await navigate("/vocabulary");
    await waitText(text.vocabulary);
    await waitText(text.startReview);

    await navigate("/reports");
    await waitText(text.reports);
    await waitText(text.reportDetails);

    await navigate("/");
    await evalJs('localStorage.clear(); location.href = "/"; true');
    await waitTitle("EnglishStudy Studio");
    await sleep(2_000);
    await fill('input[type="email"]', "admin@example.com");
    await fill('input[type="password"]', "Admin123$");
    await submitLoginForm();
    await waitPath("/dashboard");
    await navigate("/admin");
    await waitText(text.adminTitle);
    await waitText(text.newSentence);
    await waitText(text.batchImport);

    await setViewport(390, 844, true);
    const mobilePages = [
      { path: "/dashboard", expectedText: text.dashboard, label: "mobile dashboard" },
      {
        path: "/dictation?mode=advanced",
        expectedText: text.advancedDictation,
        label: "mobile dictation",
      },
      { path: "/vocabulary", expectedText: text.vocabulary, label: "mobile vocabulary" },
      { path: "/reports", expectedText: text.reports, label: "mobile reports" },
      { path: "/admin", expectedText: text.adminTitle, label: "mobile admin" },
    ];

    for (const pageCheck of mobilePages) {
      await navigate(pageCheck.path);
      await waitText(pageCheck.expectedText);
      await assertNoHorizontalOverflow(pageCheck.label);
    }

    passed = true;
    console.log(
      JSON.stringify(
        {
          status: "passed",
          baseUrl,
          checkedViewports: ["desktop:1365x900", "mobile:390x844"],
        },
        null,
        2,
      ),
    );
  } finally {
    try {
      ws?.close();
    } catch {
      // Browser shutdown should still continue.
    }

    try {
      browser.kill();
    } catch {
      // Browser may already be gone.
    }

    await waitForExit(browser);

    try {
      await rm(profileDir, {
        recursive: true,
        force: true,
        maxRetries: 5,
        retryDelay: 300,
      });
    } catch (error) {
      if (!passed) {
        throw error;
      }

      console.warn(`Warning: could not remove temporary browser profile: ${error.message}`);
    }
  }
}

await main();
