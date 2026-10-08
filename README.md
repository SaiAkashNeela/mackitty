# MacKitty 🐱
> A calmer, cleaner, faster Mac. Zero bloat, zero telemetry.

MacKitty is a modern, lightweight native macOS cleaner and live hardware monitor built with SwiftUI and AppKit. It pairs a clean, light one-screen dashboard with a compact menu bar popover to keep your Mac running smoothly.

---

## ⭐️ Credits & Inspiration

MacKitty is proudly **inspired by and built on top of [Mole](https://github.com/tw93/mole)** by [@tw93](https://github.com/tw93).

Mole is an outstanding, ultra-fast command-line cleaner and optimization utility for macOS. MacKitty acts as a native desktop companion for Mole, bringing:
- A one-screen dashboard with storage, system health and cleanup history charts
- Granular review with safe category checkboxes and Finder deep-links
- Live hardware telemetry (CPU, memory, disk, battery, network)
- An Apple Menu Bar tray companion with a live mini dashboard popover
- Automatic detection and warnings for locked caches in open apps (Firefox, Chrome, Safari, Xcode)

Huge thanks to tw93 and the open-source contributors behind the Mole CLI!

---

## 🛡️ Safety Guarantees: Zero Mac-Breaking Deletions

MacKitty is architected around **strict non-destructive safety principles**:

| Safety Feature | How MacKitty Protects Your Mac |
| :--- | :--- |
| **Dry-Run Preview First** | Scanning only measures folders (and runs `mo clean --dry-run` when Mole is installed). **Zero files are removed** during a scan. |
| **Review & Confirm** | Nothing is deleted automatically. You review every area, its path and size, and confirm before anything is removed. Mole's broader `mo clean` set is a separate opt-in row ("Mole Deep Clean"). |
| **Curated Safe Paths Only** | Cleanup is restricted to regenerable user caches (`~/Library/Caches`), developer artifacts (Xcode `DerivedData`, `~/.npm`) and logs (`~/Library/Logs`). Apple's own caches (`com.apple.*`, e.g. iCloud) and caches of apps that are currently running are always skipped. MacKitty **never touches `/System`, `/Library`, `/Applications`, or personal directories (Documents, Desktop, Downloads, Photos, iCloud)**. |
| **Active App Lock Protection** | Automatically detects when browsers (Firefox, Chrome, Safari, Brave) or developer tools (Xcode) are open, warning you rather than attempting to purge locked databases or causing app crashes. |
| **Standard User Privileges Only** | MacKitty runs entirely with your normal user permissions. It **never requests `sudo` or root permissions**, installs no persistent background daemons, and injects no kernel extensions. |
| **Instant Cancellation** | Scans and cleanups can be cancelled at any moment; a cancelled run can never resume or apply stale results. |
| **Verified Updates** | The updater only installs a build that is signed by MacKitty's Developer ID team, has the MacKitty bundle ID, passes Gatekeeper (notarized) and was downloaded from GitHub over HTTPS. |

---

## ✨ Features

- **One-Screen Dashboard:** Storage donut (used / reclaimable / free), live CPU and memory charts, battery and network status, a per-cleanup bar chart and lifetime totals — no scrolling.
- **Guided Scan & Clean:** Progress with live file counts and paths, then a sortable review table and a confirmation before anything is removed.
- **Menu Bar Popover:** Click the cat icon for storage, live vitals and a one-click Scan.
- **Safe Cleanup Areas:**
  - Xcode Derived Data
  - Safari, Chrome and Firefox caches
  - npm & Node cache
  - User app logs
  - Other app caches (excluding Apple and running apps)
  - Docker dangling images (when Docker is installed)
  - Mole's full clean set (opt-in, when Mole is installed)
- **Apps Manager:** Search installed applications, reveal them in Finder, or move them to the Trash.
- **Verified Auto-Updater:** Checks GitHub Releases and installs signed, notarized updates in place.
- **100% Private:** No accounts, no data collection, no telemetry, no analytics.

---

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode 15+ or Swift 5.10+ command line tools
- *(Recommended)* Mole CLI engine installed via Homebrew:
  ```bash
  brew install mole
  ```
  *(Note: If Mole is not installed, MacKitty runs in safe preview mode with guided instructions.)*

### Build & Run
Clone the repository and launch the app using the bundled build script:

```bash
# Build and launch MacKitty
./script/build_and_run.sh run

# Verify compilation and process startup
./script/build_and_run.sh --verify
```

### Project Layout
- `Sources/MoleMate/Views/` — SwiftUI screens (`SimpleDashboardView.swift` is the main window, `TrayMiniDashboardView.swift` the menu bar popover)
- `Sources/MoleMate/Support/Theme.swift` — design tokens (colours, type, card and button styles)
- `Sources/MoleMate/Services/` — native cleaner, Mole CLI bridge, system monitor, updater
- `website/` — marketing site with an interactive demo of the app (after editing `styles.css` or `app.js`, run `./script/stamp_website_assets.sh` so browsers don't reuse a cached copy)
- `AppStore/`, `script/build_appstore.sh`, `docs/app-store-submission.md` — sandboxed Mac App Store build (on hold)

---

## 🌐 Contact & Support

- **Website:** [mackitty.com](https://mackitty.com)
- **Email Support:** [hello@mackitty.com](mailto:hello@mackitty.com)
- **CLI Core Engine:** [github.com/tw93/mole](https://github.com/tw93/mole)
