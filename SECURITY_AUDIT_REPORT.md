# Security Audit Report — MacKitty website

| | |
|---|---|
| **Date** | 2026-11-19 |
| **Commit audited** | 63c0275 on main |
| **Remediation branch** | claude/tender-pascal-if9fzu |
| **Scope** | `website/` (https://mackitty.com, Cloudflare Pages), repo docs, secrets across the repo and history, and the release workflow `.github/workflows/build-notarize.yml`. The Swift app in `Sources/` was **not** audited or changed: it only builds on macOS, so changes there couldn't be verified here. |
| **Auditor** | Claude (Ironclad skill) |

## 1. Executive summary
The website is a static page with no server code, logins or user data, so its attack surface is small and no critical or high issues were found. The most important problems were trust and visibility ones. The privacy notice said the site used no trackers, though it loads PilotFox analytics. Every unknown URL answered with the homepage and HTTP 200. Link previews used a heavy square icon. The release workflow ran tag-pinned third-party actions while holding the Apple signing certificate. All 11 findings are fixed on the branch, each in its own commit with a regression check, and the page looks and behaves the same as before. Two things still need you: confirm the new privacy wording, and refresh the social-preview caches after you deploy.

| Severity | Found | Fixed | Open |
|---|---|---|---|
| Critical | 0 | 0 | 0 |
| High | 0 | 0 | 0 |
| Medium | 2 | 2 | 0 |
| Low | 1 | 1 | 0 |
| Info | 0 | — | — |

Also fixed (not counted above): 6 SEO, 1 social-preview and 1 documentation finding.

## 2. Open action items (human required)
1. **Confirm the privacy wording (SEC-001).** It now says the site uses PilotFox to count visits and clicks and sets no cookies. Check that this matches your PilotFox settings, and decide whether EU visitors need a consent banner.
2. **After deploying, refresh link-preview caches (SOC-001):** [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/) ("Scrape Again"), [LinkedIn Post Inspector](https://www.linkedin.com/post-inspector/), and paste the URL into the X composer.
3. **Submit the sitemap** in Google Search Console and Bing Webmaster Tools.
4. **When merging to `main`, put `[skip ci]` in the merge commit message.** This branch edits the release workflow, so otherwise the merge builds and publishes a new GitHub release with an unchanged app.
5. **After deploying, check the live headers**: `curl -sI https://mackitty.com/` should show `content-security-policy`, and `curl -sI https://mackitty.com/nope` should return `404`. If you later turn on a Cloudflare feature that injects scripts (Web Analytics, Rocket Loader, Bot Fight Mode JS detections), add its origin to `website/_headers`.

## 3. System overview
- **Stack**: one static page (`website/index.html`, `app.js` interactive demo, `styles.css`) plus assets, robots/sitemap/llms files. No build step, no backend, no forms, no cookies set by first-party code.
- **Hosting**: Cloudflare Pages (confirmed from response headers). `website/` is the output directory. `http://` and `www.` redirect to `https://mackitty.com/` with a 301.
- **Third parties**: PilotFox analytics (`https://pilotfox.app/api/s.js`), which sends page views, clicks, outbound links and web-vitals to `pilotfox.app`. Download links go to GitHub Releases.
- **Untrusted input**: only the URL hash (`#privacy`/`#terms`, checked against a fixed map) and the demo's apps search box. Both are escaped or allow-listed; the smoke test checks that the search box doesn't render HTML.
- **Release pipeline**: GitHub Actions on `main` builds, signs, notarizes and publishes the DMG. Signing and notarization secrets are in job-level env.

## 4. Methodology
Phases 0–6 of Ironclad. Recon of the repo, the live site's headers and status codes, and the PilotFox script's behaviour (read-only). Automated: `run_scanners.sh` (only the grep secret-pattern fallback was available: gitleaks, trufflehog, semgrep, osv-scanner, trivy, zizmor and actionlint aren't installed), plus a manual regex sweep of the full git history for keys. `check_seo.py`, `check_social_meta.py` and `check_docs.py` ran against a local server. Manual review covered `index.html`, the `app.js` DOM sinks (`innerHTML` with `esc()`), the JSON-LD, the crawler files and the CI workflow.

New repeatable checks: `script/check_website.py` (45 static checks) and `script/website_smoke_test.js`. The smoke test serves `website/` as Pages would (with `_headers`, `_redirects` and `404.html`), then drives the demo in Chromium, failing on JS errors, CSP violations or broken behaviour. PilotFox beacons were verified under the CSP by serving the page as `mackitty.com` inside the test browser, with the beacons intercepted so no fake visits were recorded.

**Limitations**: no Lighthouse/field Core Web Vitals data. The Swift app is out of scope. The CI change can only be fully confirmed by a run on GitHub's macOS runner.

## 5. Findings

### SEC-001 — Privacy notice says "no cookies or trackers" while the site loads analytics
| | |
|---|---|
| **Severity** | Medium |
| **Status** | Fixed (wording needs your confirmation) |
| **CWE** | CWE-359: Exposure of Private Personal Information to an Unauthorized Actor |
| **OWASP** | A04:2021 Insecure Design |
| **Location** | `website/index.html:910` (privacy modal) |
| **Compliance** | GDPR Art. 13 (transparency) |

**Description** — Commit 228ddcb added the PilotFox analytics script. The privacy modal still said "No accounts, analytics, tracking or telemetry" and "This website uses no cookies or trackers". PilotFox records page views, button clicks, outbound link clicks and web-vitals.
**Attack path** — not an exploit. Every visitor is told they aren't tracked while they are.
**Impact** — misleading visitors, and potentially App Store reviewers: `docs/app-store-submission.md` uses `https://mackitty.com/#privacy` as the app's privacy policy.
**Remediation** — the notice now names PilotFox and what it counts, and the "collects nothing" line is scoped to the app.
**Verification** — `check_website.py` fails if any third-party script's vendor isn't named in the privacy modal. Commit `3d65407`.

### SEC-003 — Release workflow runs tag-pinned actions with the signing certificate in reach
| | |
|---|---|
| **Severity** | Medium |
| **Status** | Fixed |
| **CWE** | CWE-829: Inclusion of Functionality from Untrusted Control Sphere |
| **OWASP** | A08:2021 Software and Data Integrity Failures |
| **Location** | `.github/workflows/build-notarize.yml:47,95,302,310` |

**Description** — `APPLE_CERTIFICATE_BASE64`, its password and the notarization credentials are set in job-level `env`, so every step can read them, including third-party `softprops/action-gh-release@v2`. Actions were referenced by mutable tags.
**Attack path** — the action's tag is moved, or its maintainer account is compromised → the next push to `main` runs the new code with the secrets → it exfiltrates the Developer ID certificate.
**Impact** — malware signed as MacKitty, or a malicious release published.
**Remediation** — every action is pinned to the commit SHA its tag points to today, so behaviour is identical. Moving the secrets to step-level env is listed under Recommendations.
**Verification** — YAML validated; SHAs resolved with `git ls-remote`. Commit `ba75f05`.

### SEC-002 — No CSP, HSTS or clickjacking protection
| | |
|---|---|
| **Severity** | Low |
| **Status** | Fixed |
| **CWE** | CWE-693: Protection Mechanism Failure; CWE-1021: Improper Restriction of Rendered UI Layers |
| **OWASP** | A05:2021 Security Misconfiguration |
| **Location** | `website/_headers` (new) |

**Description** — the live site only had Cloudflare Pages' default `nosniff` and `referrer-policy` headers.
**Impact** — no second line of defence if a script source is compromised, and the site could be framed for clickjacking.
**Remediation** — `website/_headers` adds:
- a CSP allowing `'self'` plus `https://pilotfox.app` for scripts and beacons, with no `unsafe-eval` or inline scripts, `frame-ancestors 'none'` and `object-src 'none'`;
- HSTS for one year, without `includeSubDomains`/preload, so other subdomains are unaffected;
- `X-Frame-Options: DENY`, a `Permissions-Policy` and COOP.

`style-src` keeps `'unsafe-inline'` because the demo sets inline `style` attributes.
**Verification** — the smoke test reports no CSP violations, and the demo, search, modals and analytics beacons all still work. Commit `c604677`.

## 6. Social sharing & link previews

| Page | og:title | og:image (size / dimensions) | twitter:card | Server-rendered? | Status |
|---|---|---|---|---|---|
| `/` | MacKitty — Allow Kitty to Take Care of Your Mac | `og-image.jpg` 40 KB, 1200×630, with alt | summary_large_image | Yes (static HTML) | ✅ |

### SOC-001 — Preview image was a 1024×1024, 853 KB square icon with no alt text
**Problem** — `og:image`/`twitter:image` used `logo.png`. It was cropped in large cards, and WhatsApp may drop images over about 300 KB.
**Fix** — a new 1200×630 card (app icon + tagline, kept to the centre so square crops still work) with `og:image:width/height/type/alt`, `twitter:image:alt` and `og:locale`. Commit `be3c234`.
**Re-scrape** — see Open action item 2. `check_social_meta.py` against the live URL will only pass after deployment, because `og-image.jpg` isn't on production yet.

## 7. Reliability: caching & rate limiting
Not applicable: there is no server code, API, cache layer or form to rate-limit. Static assets are served by Cloudflare. `styles.css` and `app.js` are cache-busted with content-hash query strings, and `check_website.py` now verifies those stamps.

**Cache inventory** — none (static hosting only).
**Rate-limit coverage** — no endpoints.

## 8. Documentation
| File | Status | Notes |
|---|---|---|
| README.md | Updated | Website section: Pages files, crawler files, how to run the two checks |
| AGENTS.md | Created | Verified commands, website conventions (CSP, privacy, SEO files), app safety rules |
| CLAUDE.md (imports @AGENTS.md) | Created | `@AGENTS.md` |
| .env.example | Created | `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` for `package_and_notarize_local.sh` |

### DOC-001 — No agent instructions; local signing env vars undocumented
**Problem** — no AGENTS.md or CLAUDE.md, and `script/package_and_notarize_local.sh` reads three env vars that weren't documented anywhere. The agent files in `.agents/skills/hallmark` were reviewed and contain no dangerous instructions. **Fix** — commit `16f1bda`. `check_docs.py` passes.

## 9. SEO & AI search

| Check | Status | Notes |
|---|---|---|
| robots.txt (allow all, Sitemap line) | ✅ | Already allowed all crawlers, including AI crawlers |
| Search & AI crawlers reach the site (CDN/WAF) | ✅ | Googlebot, Bingbot, GPTBot, OAI-SearchBot, ClaudeBot, Claude-SearchBot and PerplexityBot all get 200 (spoofed-UA test against production) |
| sitemap.xml / index (valid, canonical URLs only, real lastmod) | ✅ | lastmod updated (SEO-006) |
| llms.txt / llms-full.txt | ✅ | Fixed (SEO-005) |
| Server-rendered content & metadata | ✅ | Static HTML |
| Titles, descriptions, canonicals, h1, lang | ✅ | Fixed lengths (SEO-004) |
| Structured data (JSON-LD) | ✅ | Fixed dangling reference (SEO-003) |
| hreflang (if multilingual) | n/a | English only |
| Core Web Vitals (LCP / INP / CLS) | ⚠️ not measured | 850 KB of icon weight removed (SEO-002); see Recommendations for the 3.8 MB hero video |

### SEO-001 — Soft 404s: every unknown URL returned the homepage with HTTP 200
**Impact** — Medium. **Problem** — without a `404.html`, Cloudflare Pages runs in SPA mode. `/anything`, `/favicon.ico`, `/llms-full.txt`, `/README.md` and the deleted `/privacy.html` and `/terms.html` all returned the full homepage with 200. **Fix** — a `noindex` `404.html` (real 404 status), plus `_redirects`: the old legal URLs → `/#privacy` and `/#terms` (which open the modals), `/favicon.ico` → the favicon. Commit `f9c33b6`.

### SEO-002 — 853 KB logo loaded for 22–54px icons
**Impact** — Medium. **Problem** — five `<img>` tags and the apple-touch-icon used the 1024×1024 PNG. **Fix** — a 56 KB 256px copy, a 180px apple-touch-icon, explicit `width`/`height`, and a lazy-loaded footer icon. Rendered sizes are identical (screenshots compared). Commit `977729d`.

### SEO-003 — JSON-LD `WebSite.publisher` referenced an undefined `@id`
**Impact** — Low. **Fix** — added the `Organization` node, referenced it from the app, and added `@id`/`url`/`downloadUrl` to `SoftwareApplication`. Commit `2cfe9a6`. **Follow-up** — validate with Google's Rich Results Test after deployment.

### SEO-004 — Title (72) and description (178) too long
**Impact** — Low. **Fix** — title "MacKitty — Fast, Safe & Free Native Mac Cleaner" (47 chars). The new description (154 chars) lists only what the app really cleans; the old one mentioned "Homebrew residue", which the app doesn't target directly. Your tagline stays in the H1 and `og:title`. Commit `1a8c3fd`.

### SEO-005 — llms.txt without Markdown links; no llms-full.txt
**Impact** — Low (cheap extra, not a ranking factor). **Fix** — commit `0f00365`.

### SEO-006 — Stale sitemap lastmod
**Impact** — Low. **Fix** — commit `f88ec78`.

## 10. Merge gate
## Ironclad merge gate: ✅ READY TO MERGE

Base: `main` · Commit: `00c31bc` · 2026-11-19T13:13Z

| Check | Result | Details |
|---|---|---|
| Clean working tree | ✅ pass |  |
| Up to date with origin/main | ✅ pass |  |
| python3 script/check_website.py | ✅ pass | `python3 script/check_website.py` |
| node script/website_smoke_test.js | ✅ pass | `node script/website_smoke_test.js` |
| No new skips/suppressions | ✅ pass |  |
| No secrets in branch | ⚠️ warn | pattern check only — gitleaks not installed |
| Dependency audit | ⚠️ warn | no audit tool available for this stack — note in PR |
| No open critical/high findings | ✅ pass |  |
| Docs up to date | ✅ pass | check_docs.py |

_Gate by [Ironclad](https://github.com/saiakashneela) · Sai Akash Neela_

The gate ran without `--url`, because `check_social_meta.py` fetches `og:image` from production, which won't have `og-image.jpg` until this branch is deployed. The SEO and social checks passed against a local server (SEO 22/22; social 10/10 on the built HTML).

## 11. Remediation log
| ID | Title | Commit | Test added | Notes |
|---|---|---|---|---|
| — | Website checks | 1e07d02 | `script/check_website.py`, `script/website_smoke_test.js` | Written first; failed on every finding below |
| SEC-001 | Privacy notice discloses PilotFox | 3d65407 | check_website.py (privacy vs. scripts) | Wording to confirm |
| SEC-002 | Security headers | c604677 | smoke test (CSP violations, demo) | |
| SEO-001 | Real 404s + legacy redirects | f9c33b6 | smoke test (404, redirects) | |
| SOC-001 | 1200×630 preview image | be3c234 | check_website.py (size, weight, alt) | Re-scrape after deploy |
| SEO-002 | 256px logo | 977729d | check_website.py (image weight) | Visual diff identical |
| SEO-003 | JSON-LD Organization | 2cfe9a6 | check_website.py (@id refs) | |
| SEO-004 | Title/description length | 1a8c3fd | check_website.py | |
| SEO-005 | llms.txt / llms-full.txt | 0f00365 | check_website.py | |
| SEO-006 | sitemap lastmod | f88ec78 | check_website.py | |
| DOC-001 | AGENTS.md, CLAUDE.md, .env.example, README | 16f1bda | check_docs.py | |
| — | CI: skip app build for website-check-only changes | 15ae3f1 | — | Same pattern as 85ca56d |
| SEC-003 | Pin GitHub Actions to SHAs | ba75f05 | YAML parse | |

## 12. Scanner results not reported as findings
- Grep secret patterns: 0 matches. No keys, tokens or private keys in the tree or in the git history (manual regex sweep).
- `temporary-build-keychain-pass` in the workflow: the password of a throwaway keychain created on the CI runner, not a credential.
- `app.js` `innerHTML` sinks: all interpolate either constants or values passed through `esc()`. No XSS.
- The `#hash` → modal lookup in `app.js` uses `name in modals`, so `#toString` throws a harmless console error. It isn't exploitable, so it wasn't changed.

## 13. Recommendations
- **CI secrets**: move the Apple secrets from job-level `env` to only the steps that need them, and set `permissions: contents: write` only on the release step's job. Add Dependabot for `github-actions` so the pinned SHAs get update PRs.
- **Secret scanning**: enable GitHub secret scanning and push protection, and add a gitleaks pre-commit hook.
- **Third-party script**: PilotFox is loaded without Subresource Integrity, which isn't possible for a versionless URL. The CSP limits where it can send data. If PilotFox offers a self-hosted or versioned script, pin it.
- **Performance**: the hero video `assets/bg.mp4` (3.8 MB, `preload="auto"`) loads on every visit. Consider `preload="metadata"` or a smaller encode, and run PageSpeed Insights after deployment.
- **Caching**: `styles.css`/`app.js` are content-stamped, so they could get `Cache-Control: max-age=31536000, immutable` in `_headers`. Only do this if the stamp script is always run (it's manual today).
- **CI for the site**: run `python3 script/check_website.py` and `node script/website_smoke_test.js` in a GitHub Actions job on pull requests, and make it a required check.
- **Discovery**: verify the site in Bing Webmaster Tools and enable IndexNow (Cloudflare has a toggle: Crawler Hints).

---
*Audit performed with Ironclad by [Sai Akash Neela](https://saiakashneela.com) · [GitHub](https://github.com/saiakashneela) · [X](https://x.com/thesaiakash)*
