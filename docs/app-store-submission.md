# Submitting MacKitty to the Mac App Store

MacKitty ships two builds from the same code:

| | Direct download (today) | Mac App Store |
|---|---|---|
| Signed with | Developer ID Application | Apple Distribution |
| Sandbox | No | **Required** (`AppStore/MacKitty.entitlements`) |
| Updates | Built-in updater | App Store |
| Mole CLI, Docker cleanup, Terminal helpers | Yes | No (sandbox can't launch other tools) |
| Folder access | Direct | User grants their home folder once |
| Build command | CI / `script/package_and_notarize_local.sh` | `script/build_appstore.sh` |

The App Store build is compiled with `-DAPPSTORE` (`isAppStoreBuild` in
`Sources/MoleMate/Support/SandboxAccess.swift`), which turns off the updater,
Mole CLI, Docker, Terminal automation and the move-to-Applications prompt.

## 1. One-time setup in your Apple Developer account

1. **Bundle ID** — Certificates, Identifiers & Profiles → Identifiers → confirm
   `com.mackitty.app` exists (explicit App ID). If it was only used for Developer ID,
   it can be reused for the App Store.
2. **Certificates** — you already have *Apple Distribution*. Create a
   **Mac Installer Distribution** certificate (needed to sign the `.pkg`), download it
   and double-click to add it to Keychain. It appears as
   `3rd Party Mac Developer Installer: Sai Akash Neela (8GG7J6LQZL)`.
3. **Provisioning profile** — Profiles → `+` → **Mac App Store Connect** → App ID
   `com.mackitty.app` → Apple Distribution certificate → download, e.g.
   `MacKitty_AppStore.provisionprofile`.
4. **App Store Connect API key** (optional, for command-line upload) — App Store
   Connect → Users and Access → Integrations → App Store Connect API → generate a key
   with the *App Manager* role. Save `AuthKey_<KEYID>.p8` to
   `~/.appstoreconnect/private_keys/`.

## 2. Create the app record in App Store Connect

My Apps → `+` → New App → Platform **macOS**, name **MacKitty** (must be unique on
the store; have a fallback such as "MacKitty – Mac Cleaner"), primary language, bundle
ID `com.mackitty.app`, SKU `mackitty-macos`.

Fill in:
- **Category**: Utilities.
- **Privacy policy URL**: `https://mackitty.com/privacy.html`.
- **App Privacy** questionnaire: *Data Not Collected* (the App Store build makes no
  network requests and has no telemetry).
- **Screenshots**: at least one at 1280×800, 1440×900, 2560×1600 or 2880×1800.
- **Description, keywords, support URL** (`https://mackitty.com`), **age rating**
  (4+), **pricing**.
- **App Review notes** — explain the home-folder prompt, e.g.:
  > MacKitty finds rebuildable caches and logs. On first scan it asks the user to
  > choose their home folder (via the standard open panel) so the sandboxed app can
  > read ~/Library/Caches and ~/Library/Logs. Nothing is deleted until the user
  > reviews the list and confirms.

## 3. Build, validate and upload

```bash
MAS_PROVISIONING_PROFILE=~/Downloads/MacKitty_AppStore.provisionprofile \
  ./script/build_appstore.sh 1
```

This produces `dist/appstore/MacKitty.pkg`. Upload it either with **Transporter**
(free on the Mac App Store; drag the pkg in) or from the command line:

```bash
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
MAS_PROVISIONING_PROFILE=~/Downloads/MacKitty_AppStore.provisionprofile \
  ./script/build_appstore.sh 1 --upload
```

Every upload needs a higher build number (the first argument). Bump `VERSION` for
a new marketing version.

## 4. Test, then submit

1. After processing (~15–60 min) the build appears under **TestFlight**. Install it
   via TestFlight on your Mac and run a full scan → review → clean.
2. On the app's version page, pick the build, then **Add for Review** →
   **Submit to App Review**. Review usually takes 1–3 days.

## Review risks to know about

- **Guideline 2.4.5 (sandbox, no self-updating, no launching other apps)** — handled by
  the `APPSTORE` build.
- **Minimum functionality** — the sandboxed build still scans and cleans browser, Xcode,
  npm, log and app caches after the home-folder grant, plus the live system dashboard.
- **Cleaner apps get extra scrutiny**: avoid claims like "speeds up your Mac" in the
  description; describe exactly what is removed.
- The name "MacKitty" uses "Mac"; Apple sometimes rejects names that imply an Apple
  product. If that happens, use a subtitle style such as "MacKitty: Cache Cleaner".
