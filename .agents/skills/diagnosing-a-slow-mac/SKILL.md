---
name: diagnosing-a-slow-mac
description: Use when a Mac hangs, beachballs, feels slow, runs hot or drains battery, when the user asks what is eating CPU, memory, GPU or disk, when asked to free disk space or clean caches, or when designing MacKitty features that diagnose or clean a Mac.
---

# Diagnosing a Slow Mac

## Overview
Collect facts read-only first, rank causes by measured impact, then clean only with consent. **Hangs on Apple Silicon are usually memory pressure plus a nearly full disk**, not CPU: swap can't grow, so everything stalls.

## 1. Read-only checks (run in parallel)
| Check | Command | Red flag |
|---|---|---|
| RAM / swap | `memory_pressure`, `sysctl vm.swapusage`, `top -l1 -n0 \| grep PhysMem` | swap used ≈ total; <200 MB unused; compressor GBs |
| Disk | `df -h /System/Volumes/Data` | >90% used or <15 GB free |
| CPU hogs | `top -l 2 -s 2 -o cpu -n 20 -stats pid,command,cpu,mem` | anything steady >10% while "idle" |
| RAM by app | `ps -axo rss=,comm=`, grouped per app (browsers have many helpers) | browser tabs at GBs |
| VMs | `ps` for `com.apple.Virtualization`, `docker stats --no-stream` | Docker VM holds its RAM even after containers stop |
| Crash loops | `ls /Library/Logs/DiagnosticReports`, `launchctl print system/<label>` | same daemon crashing repeatedly (`runs = 20000+`) |
| Heat / sleep | `pmset -g therm`, `pmset -g assertions` | throttling, stuck sleep blockers |
| Uptime | `uptime` | days of uptime plus GBs of swap: a restart clears it |

Use the second `top` sample. The first sample's CPU % is meaningless.

## 2. Usual causes → fixes
- **Docker Desktop VM**: quit it, or cap Resources → Memory at 4 GB.
- **Browser tabs**: find heavy tabs in `about:processes` / Task Manager; avoid running two browsers.
- **Uninstalled app with a leftover launchd daemon**: remove the `/Library/LaunchDaemons` plist and its helper binary (needs sudo, so the user runs it).
- **Always-animating menu bar/desktop apps**: quit them. See keeping-mac-apps-idle-cheap.
- **Disk**: see the cleanup table below.

## 3. Cleanup targets (largest usually first)
| Target | Regenerates? | Check first |
|---|---|---|
| `~/Library/Developer/CoreSimulator` (runtimes + devices) | runtimes re-download | keep latest runtime |
| `node_modules`, `target/`, `android/app/build` | yes, slower next build | not git-tracked; release APKs saved |
| `~/.gradle/caches`, `~/.cache/uv`, `~/.bun/install/cache`, `~/.npm` | yes | no process holds a lock (`uv` MCP servers do) |
| Android emulators `~/.android/avd` | no (recreate) | user consent |
| Old app data (e.g. `~/.gemini/*`) | no | newest file mtime **and** `lsof +D` |
| Merged git worktrees / branches | n/a | clean status, merged PR, `git branch -d` only |

## Safety rules (each was broken once)
- **Judge "old" by evidence, not by name**: newest mtime, `lsof +D`, process args (`--app_data_dir=...`).
- Show what will be deleted and get a yes; confirm again for anything irreversible.
- Check `git ls-files` before deleting build output; never edit shared repo config except on a branch.
- macOS blocks deletes in `~/Library/Containers/*` (even Finder fails); they are tiny, leave them.
- zsh aborts the whole command on an unmatched glob; `find` may be aliased (use `/usr/bin/find`).
- Never read secret values while exploring (`.env`, keychains).

## MacKitty mapping
Memory/swap: `host_statistics64` + `sysctl vm.swapusage`. Disk: `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`. Top processes: `proc_listpids` + `proc_pid_rusage`. Crash loops: count `.ips` files per process in DiagnosticReports. Implemented: developer caches, code-project cleanup and old Simulator runtimes (`Services/NativeCleanerService.swift`, `ProjectArtifactScanner.swift`, `RunningProcesses.swift`), the Speed tab (`MemoryReport.swift`) and complete uninstall (`AppLeftovers.swift`). Also iOS Device Support, Expo cache, Android emulators, Trash and Python venvs/caches. Still to build: crash-loop detection.
