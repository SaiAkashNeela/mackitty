#!/usr/bin/env node
// Browser smoke test for website/ as Cloudflare Pages would serve it:
// applies the `/*` block of website/_headers (incl. the CSP), answers unknown
// paths with 404.html + HTTP 404, and follows website/_redirects. Then drives
// the interactive demo in Chromium and fails on any JS error, CSP violation,
// failed request, or broken behaviour.
//
// Needs Node 18+ and Playwright with Chromium:
//   npm install --no-save playwright && npx playwright install chromium
//   node script/website_smoke_test.js
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const SITE = path.join(__dirname, "..", "website");
const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".png": "image/png",
  ".jpg": "image/jpeg", ".mp4": "video/mp4", ".txt": "text/plain; charset=utf-8", ".xml": "application/xml" };

function readHeaders() {
  const out = {};
  const file = path.join(SITE, "_headers");
  if (!fs.existsSync(file)) return out;
  let inAll = false;
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line.trim() || line.trim().startsWith("#")) continue;
    if (!/^\s/.test(line)) { inAll = line.trim() === "/*"; continue; }
    if (inAll) { const i = line.indexOf(":"); out[line.slice(0, i).trim()] = line.slice(i + 1).trim(); }
  }
  return out;
}
function readRedirects() {
  const file = path.join(SITE, "_redirects");
  if (!fs.existsSync(file)) return {};
  return Object.fromEntries(fs.readFileSync(file, "utf8").split("\n").map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#")).map((l) => { const [from, to, code] = l.split(/\s+/); return [from, [to, Number(code || 302)]]; }));
}

const HEADERS = readHeaders();
const REDIRECTS = readRedirects();
const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (REDIRECTS[url.pathname]) { const [to, code] = REDIRECTS[url.pathname]; res.writeHead(code, { Location: to }); return res.end(); }
  let p = path.normalize(path.join(SITE, decodeURIComponent(url.pathname)));
  if (!p.startsWith(SITE)) { res.writeHead(400); return res.end(); }
  if (fs.existsSync(p) && fs.statSync(p).isDirectory()) p = path.join(p, "index.html");
  let status = 200;
  if (!fs.existsSync(p) || path.basename(p).startsWith("_")) {
    // Pages: 404.html with a 404 status if it exists, otherwise SPA fallback to index.html with 200
    const nf = path.join(SITE, "404.html");
    if (fs.existsSync(nf)) { status = 404; p = nf; } else { p = path.join(SITE, "index.html"); }
  }
  res.writeHead(status, { ...HEADERS, "Content-Type": TYPES[path.extname(p)] || "application/octet-stream" });
  fs.createReadStream(p).pipe(res);
});

const problems = [];
const fail = (m) => { problems.push(m); console.log("  [FAIL] " + m); };
const pass = (m) => console.log("  [PASS] " + m);

(async () => {
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  console.log(`=== website smoke test (${base})`);
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await page.addInitScript(() => {
      window.__csp = [];
      document.addEventListener("securitypolicyviolation", (e) => window.__csp.push(`${e.violatedDirective} ${e.blockedURI}`));
    });
    page.on("console", (m) => { if (m.type() === "error") fail("console error: " + m.text()); });
    page.on("pageerror", (e) => fail("page error: " + e.message));
    page.on("requestfailed", (r) => {
      const err = (r.failure() || {}).errorText || "";
      // media requests are routinely aborted when a video is paused/replaced
      if (!/ERR_ABORTED/.test(err) || !/\.mp4/.test(r.url())) fail(`request failed: ${r.url()} ${err}`);
    });
    page.on("response", (r) => { if (r.url().startsWith(base) && r.status() >= 400) fail(`HTTP ${r.status()} for ${r.url()}`); });

    const resp = await page.goto(base + "/", { waitUntil: "networkidle" });
    resp.status() === 200 ? pass("home page 200") : fail("home page status " + resp.status());
    if (HEADERS["Content-Security-Policy"]) (resp.headers()["content-security-policy"] ? pass("CSP header served") : fail("CSP header missing"));

    await page.click("#btn-start-scan");
    await page.click("#btn-modal-confirm"); // simulated macOS permission sheet
    await page.waitForSelector("#screen-triage.active", { timeout: 20000 }).catch(() => {});
    (await page.locator("#screen-triage.active").count()) > 0 ? pass("demo scan produces results") : fail("demo scan produced no results");

    await page.click('[data-app-tab="apps"]');
    await page.fill("#apps-search", "xcode");
    (await page.locator("#mk-apps-list .mk-app-row").count()) === 1 ? pass("apps search filters the list") : fail("apps search did not filter");
    await page.fill("#apps-search", '<img src=x onerror="window.__xss=1">');
    await page.waitForTimeout(200);
    (await page.evaluate(() => window.__xss)) ? fail("apps search renders HTML (XSS)") : pass("apps search escapes input");

    await page.goto(base + "/#privacy");
    await page.waitForTimeout(300);
    (await page.evaluate(() => document.getElementById("legal-privacy").open)) ? pass("#privacy opens the privacy modal") : fail("#privacy did not open the modal");

    const csp = await page.evaluate(() => window.__csp);
    csp.length ? fail("CSP violations: " + csp.join(", ")) : pass("no CSP violations");

    const nf = await browser.newPage();
    const r404 = await nf.goto(base + "/definitely-not-a-page");
    r404.status() === 404 ? pass("unknown URL returns 404") : fail("unknown URL returned " + r404.status());
    (await nf.locator('a[href="/"]').count()) > 0 ? pass("404 page links home") : fail("404 page has no link home");

    for (const [from, [to]] of Object.entries(REDIRECTS)) {
      const r = await fetch(base + from, { redirect: "manual" });
      r.headers.get("location") === to ? pass(`${from} → ${to}`) : fail(`${from} did not redirect to ${to}`);
    }
  } finally {
    await browser.close();
    server.close();
  }
  console.log(`\nSummary: ${problems.length} fail`);
  process.exit(problems.length ? 1 : 0);
})().catch((e) => { console.error(e); server.close(); process.exit(1); });
