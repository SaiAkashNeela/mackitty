# MacKitty 🐱
> A calmer, cleaner, faster Mac. Zero bloat, zero telemetry.

MacKitty is a modern, lightweight native macOS cleaner and live hardware monitor built with SwiftUI and AppKit. It pairs a rich, transparent desktop dashboard with a sleek Apple Menu Bar mini dashboard to keep your Mac running smoothly.

---

## ⭐️ Credits & Inspiration

MacKitty is proudly **inspired by and built on top of [Mole](https://github.com/tw93/mole)** by [@tw93](https://github.com/tw93).

Mole is an outstanding, ultra-fast command-line cleaner and optimization utility for macOS. MacKitty acts as a native desktop companion for Mole, bringing:
- An interactive, animated scanning visualizer (radar sweep, live folder counters, path ticker)
- Granular triage with safe category checkboxes and Finder deep-links
- Live hardware telemetry (CPU, RAM, Disk, Battery, Wi-Fi SSID)
- An Apple Menu Bar tray companion with a live mini dashboard popover
- Automatic detection and warnings for locked caches in open apps (Firefox, Chrome, Safari, Xcode)

Huge thanks to tw93 and the open-source contributors behind the Mole CLI!

---

## 🛡️ Safety Guarantees: Zero Mac-Breaking Deletions

MacKitty is architected around **strict non-destructive safety principles**:

| Safety Feature | How MacKitty Protects Your Mac |
| :--- | :--- |
| **Dry-Run Preview First** | MacKitty always runs `mo clean --dry-run` during the scanning phase. It only inspects paths and calculates recoverable bytes—**zero files are removed** during scanning. |
| **User Triage & Review** | Nothing is deleted automatically. The user is presented with a detailed triage screen showing safe categories, total size, exact file paths, and an "Open in Finder" inspector. |
| **Curated Safe Paths Only** | Cleanup is restricted to safe, regenerable user caches (`~/Library/Caches`), developer artifacts (`DerivedData`, package manager caches), logs, and the user Trash. MacKitty **never touches `/System`, `/Library`, `/Applications`, or personal directories (Documents, Desktop, Photos, iCloud)**. |
| **Active App Lock Protection** | Automatically detects when browsers (Firefox, Chrome, Safari, Brave) or developer tools (Xcode) are open, warning you rather than attempting to purge locked databases or causing app crashes. |
| **Standard User Privileges Only** | MacKitty runs entirely with your normal user permissions. It **never requests `sudo` or root permissions**, installs no persistent background daemons, and injects no kernel extensions. |
| **Instant Cancellation** | Scans and cleanups can be cancelled at any moment with the "Cancel" button, safely terminating the underlying subprocess. |

---

## ✨ Features

- **Interactive Deep Scanner:** Live animated radar sweep and file counter ticker so you always know scanning is actively making progress.
- **Menu Bar Mini Dashboard:** Click the status bar cat icon to reveal a frosted dark glass popover showing live CPU, Memory, Disk storage, Battery health, Wi-Fi SSID, and 1-click Quick Clean.
- **Hardware Telemetry:** Real-time CPU core usage, Apple Silicon chip identification, memory pressure ratios, and disk volume capacity.
- **Safe Cleanup Areas:**
  - Application Caches & Temporary Files
  - Developer Builds (Xcode DerivedData, CocoaPods, SPM, Android)
  - Diagnostic Logs & Crash Reports
  - Browser & Web Cache Cleaners
  - System Trash bin
- **Apps Manager:** View installed applications, installation sizes, and inspect bundle paths.
- **Serverless Auto-Updater:** Checks `https://mackitty.com/api/version.json` or GitHub Releases for new updates without requiring a persistent backend server.
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

---

## 🌐 Contact & Support

- **Website:** [mackitty.com](https://mackitty.com)
- **Email Support:** [hello@mackitty.com](mailto:hello@mackitty.com)
- **CLI Core Engine:** [github.com/tw93/mole](https://github.com/tw93/mole)
