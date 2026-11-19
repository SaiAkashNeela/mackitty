# AGENTS.md

## Project
MacKitty: a native macOS cache cleaner and system monitor (Swift 5.9 / SwiftUI + AppKit, macOS 14+), plus its marketing site.

- `Sources/MoleMate/` — the app (Swift package target `MacKitty`, see `Package.swift`). `Views/`, `Services/` (cleaner, Mole CLI bridge, system monitor, updater), `Stores/`, `Support/` (`Theme.swift` holds the design tokens).
- `website/` — static site for https://mackitty.com, deployed by Cloudflare Pages with `website/` as the output directory. No build step.
- `AppStore/`, `script/build_appstore.sh`, `docs/app-store-submission.md` — sandboxed Mac App Store build (on hold).
- `.github/workflows/build-notarize.yml` — builds, signs, notarizes and releases the DMG on pushes to `main`. It ignores `website/**`, `docs/**` and `*.md`.

## Commands
- Build and launch the app (macOS only): `./script/build_and_run.sh run`
- Check that it compiles and starts: `./script/build_and_run.sh --verify`
- Website static checks (stdlib Python, any OS): `python3 script/check_website.py`
- Website browser smoke test (Node 18+ and Playwright with Chromium): `node script/website_smoke_test.js`
- After editing `website/styles.css` or `website/app.js`: `./script/stamp_website_assets.sh` (macOS `sed -i ''` and `shasum`)
- Local signed DMG: `./script/package_and_notarize_local.sh` (reads `.env`, see `.env.example`)

## Website conventions
- Cloudflare Pages files live in `website/`: `_headers` (security headers incl. CSP), `_redirects`, `404.html`. Without `404.html`, Pages answers every unknown URL with the homepage and HTTP 200.
- **CSP**: `website/_headers` only allows this origin plus `https://pilotfox.app` (analytics). Adding any third-party script, font, image, video host, iframe or fetch target means adding its origin to the matching directive, then running the smoke test. No inline `<script>` (except `application/ld+json`). If a Cloudflare feature that injects scripts (Web Analytics auto-injection, Rocket Loader, Bot Fight Mode JS detections, Email Obfuscation) is turned on, update the CSP too.
- **Privacy notice**: the `#privacy` modal in `index.html` must name every analytics or tracking service the site loads. `script/check_website.py` enforces this.
- **SEO files**: `robots.txt`, `sitemap.xml` (update `<lastmod>` when page content changes), `llms.txt` and `llms-full.txt` are hand-written. When copy in `index.html` changes, update `llms-full.txt` (and the JSON-LD FAQ if FAQ text changes).
- Title ≤ 60 chars, meta description ≤ 160. The link-preview image is `website/assets/og-image.jpg` (1200×630). If you replace it, use a new file name so platforms re-fetch it.
- On-page icons use `website/assets/logo-256.png`; keep images over 200 KB off the page.

## App safety rules (do not weaken)
- Cleanup is limited to the curated rebuildable cache/log paths listed in README.md. Never add `/System`, `/Library`, `/Applications`, or personal folders (Documents, Desktop, Downloads, Photos, iCloud), Keychain or `.git` directories.
- Scans never delete. Every removal is reviewed and confirmed by the user, and stays cancellable.
- No `sudo`/root, daemons or kernel extensions. No telemetry in the app.
- The updater must keep verifying the Developer ID team, bundle ID, Gatekeeper/notarization and an HTTPS GitHub download.

## Testing rules
- Before pushing website changes, both website checks must pass. App changes must build with `./script/build_and_run.sh --verify` on macOS.
- Never skip, delete or weaken a check to get a green run; fix the cause.

## Security rules
- Never commit secrets: `.env` is git-ignored, and CI uses GitHub Actions secrets.
- Don't print signing or notarization credentials in scripts or logs.
