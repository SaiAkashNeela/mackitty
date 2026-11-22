---
name: keeping-mac-apps-idle-cheap
description: Use when a macOS SwiftUI or AppKit app (such as MacKitty) shows CPU, energy or WindowServer load while idle, hidden or closed to the menu bar, uses more memory than expected, or before shipping anything that animates, plays video or polls on a timer.
---

# Keeping Mac Apps Idle-Cheap

## Overview
An idle app should cost ~0% CPU. Anything that draws or polls must stop when nobody can see it. **Measure before and after every change; never guess.**

## Measure
```bash
bash script/measure_idle.sh dist/MacKitty.app 20   # CPU, WindowServer, footprint, wakeups: front / hidden / closed
sample $(pgrep -x MacKitty) 5 -file /tmp/s.txt      # what is running (look under "Sort by top of stack")
footprint -p $(pgrep -x MacKitty)                   # memory by category
```
Measure an optimized build (`swift build -c release`), not debug. WindowServer % is system-wide and noisy; judge by the app's own CPU.

To find who allocated a big region: launch the binary with `MallocStackLogging=1`, get the address from `vmmap PID | grep '<category>'`, then run `malloc_history PID 0x<addr>`.

## Culprits and fixes
| Symptom in `sample` / `footprint` | Cause | Fix |
|---|---|---|
| `ViewGraph.render` + `CA::Transaction::commit` every frame | `.repeatForever` animation, `TimelineView(.animation)` | Static visuals; animate only during real work (scan/clean) |
| `com.apple.coremedia.*` threads busy while hidden | `AVPlayer` looping when off screen | Play only while on screen + app active + no Reduce Motion |
| Timer work while window closed | Polling started in `init` | Poll only while a view showing the data is on screen |
| WindowServer high while video plays | `.shadow` on a view containing video/animation | Put the shadow on a static background shape |
| One huge `CG image` region | Large `NSImage` given to AppKit (e.g. `applicationIconImage`) | Use bundle `AppIcon.icns`; size images to their display size |
| `ImageIO` MBs for a small logo | 1024px PNG decoded for a 72pt view | `CGImageSourceCreateThumbnailAtIndex` at display px (`Support/AppLogo.swift`) |
| ~13 MB `MALLOC_LARGE` a few seconds after launch | AppKit state-restoration window snapshot (`NSPersistentUIWindowSnapshotter`) | `window.isRestorable = false` when the app opens its own window anyway |

Floors on macOS 26: an empty SwiftUI window app is ~16 MB and a menu-bar-only AppKit app ~10 MB. Releasing views on close does **not** lower the footprint: malloc keeps the dirty pages. Memory saved must come from never allocating. A Rust rewrite would not help, because the cost is Apple frameworks and window buffers, not app code.

## The trap: closed ≠ gone
MacKitty's close button calls `orderOut` (`Support/MainWindow.swift`), so SwiftUI **never fires `onDisappear`**. Hidden, minimized, covered or closed windows only change **occlusion**. Use the helpers in `Support/OnScreenVisibility.swift`:

```swift
// Views: start/stop live data with on-screen state
.onScreenChange { [monitor, watchID] in monitor.setWatching(watchID, $0) }
.onDisappear { monitor.setWatching(watchID, false) }

// NSViews (video): subclass OcclusionTrackingView, gate on isOnScreen && NSApp.isActive
```

## Common mistakes
- Testing only with the window in front: idle bugs live in the hidden and closed states.
- Trusting `onDisappear` / `scenePhase` on macOS for visibility.
- Mutating SwiftUI state synchronously from `viewDidMoveToWindow` (defer it).
- Re-encoding assets before checking them: MacKitty's `bg.mp4` is already 720p/24 fps. Pausing it was the fix.

## Results (Nov 2026)
Front / hidden / closed app CPU went from 24 / 27 / 21% to under 1%. Footprint went from 93 MB to 41 MB. The cat video costs only ~2 MB, so keep it.
