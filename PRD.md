# Mac Monitor — PRD

*Working name. Owner: John. Builder: Claude Code. Date: 2026-10-31.*

## 1. Summary

A native macOS menu bar app that tells John, at a glance, whether his MacBook is healthy — and when it isn't, says what's wrong in one sentence and offers one button that fixes it. It also exposes a local, read-only MCP server so Claude (Claude Code or the Claude app) can see the same state and help explain alerts that aren't a one-button fix.

John is a product designer, not a sysadmin. Raw metrics ("10 GB", "swap") mean little on their own. Every number the app shows must come with a color and a short line of context. The product is the **verdict + the fix**, not the dashboard.

### Why it exists (origin)
A manual audit on John's M2 Max (32 GB RAM, macOS 27) found: 41 days without a restart, swap 94% full, ~10 GB compressed memory, Comet browser alone using ~10 GB across ~25 tab processes, Spotlight indexing burning ~40% of a core (thousands of `node_modules` files), a failing GeoComply background service, apps silently adding themselves to startup (Spotify, Studio by Spotify Labs), ~28 GB of disposable caches, and a degraded battery (1,450 cycles, 77% capacity, "Service Recommended") that throttles the Mac near empty. Every one of those should have been an alert with a button.

## 2. Goals / non-goals

**Goals**
- Glanceable health: menu bar icon color reflects the worst current state.
- Plain-language vitals: number + color + one line of meaning.
- Actionable alerts: each = one sentence + one primary fix button (+ snooze).
- Proactive notifications for things worth interrupting for, with the fix button inside the notification.
- Detect *changes* John would never notice (new startup items, runaway processes, junk accumulating).
- Read-only MCP server in v1 so Claude can look at the same state when an alert needs explaining.
- Featherweight: the monitor must never become a hog itself.

**Non-goals (v1)**
- No AI/LLM calls or API keys inside the app.
- No agent/chat inbox (separate project).
- No App Store distribution or sandboxing. Personal, locally built, unsandboxed app.
- No historical graphs or analytics dashboards.

## 3. Platform & architecture

- Swift + SwiftUI, `MenuBarExtra` with `.window` style. Target macOS 14+ (John runs macOS 27, Apple Silicon).
- Unsandboxed, signed locally (Developer ID or ad-hoc). Launches at login via `SMAppService.mainApp`.
- **Core engine** (`MonitorEngine`): collectors → evaluators → `[Vital]` + `[Alert]` state. UI, notifications, and MCP all read from it.
- **Fix actions** (`FixAction`): a single registry of actions (quit app, restart app, clear cache, remove startup item, empty trash, restart Mac…). Buttons and notification actions both invoke the same registry. No duplicate logic.
- **MCP**: after every sample the app writes its state as JSON files (one per tool, owner-only) to `~/Library/Application Support/MacMonitor/state/`. A bundled CLI `macmon-mcp` speaks MCP over stdio and serves those files. Nothing listens on a socket. If the files are missing or more than 5 minutes old, tools return a clear "Mac Monitor isn't running" error.
- Privileged operations (system-wide LaunchDaemons, `/Library` items, `pmset`) go through a standard macOS admin prompt (`AuthorizationServices` or `osascript … with administrator privileges`). Never store the password.

### Sampling budget
- Panel open: refresh vitals every 3–5 s.
- Panel closed: light sample every 30 s (memory, swap, CPU, battery, thermal).
- Process scan: every 30 s; sustained-load detection uses a rolling window.
- Heavy scans (cache sizes, `node_modules`, Trash, startup item diff): every 6 h, at launch, and on demand ("Rescan").
- Target: <1% average CPU, <80 MB RAM. Show the app's own usage in Settings > About.

## 4. Data sources (implementation notes — verify on macOS 27)

| Data | Source |
|---|---|
| Memory pressure | `DispatchSource.makeMemoryPressureSource` + `kern.memorystatus_vm_pressure_level` sysctl |
| Memory used / compressed / cached | `host_statistics64(HOST_VM_INFO64)` |
| Swap | `sysctl vm.swapusage` |
| CPU total | `host_processor_info` deltas |
| Per-process CPU/mem | `libproc` (`proc_listpids`, `proc_pid_rusage`, `proc_pidpath`). Group helpers into their parent `.app` bundle (e.g. 25 "Comet Helper (Renderer)" → "Comet"). |
| Battery charge, cycles, capacity, condition | IOKit `AppleSmartBattery` (`CycleCount`, `AppleRawMaxCapacity`, `DesignCapacity`) + `IOPSCopyPowerSourcesInfo` (health/condition, charging, time remaining) |
| Thermal | `ProcessInfo.thermalState` |
| Uptime | `sysctl kern.boottime` |
| Disk free | `URLResourceValues.volumeAvailableCapacityForImportantUsage` on `/` |
| Sleep blockers | `IOPMCopyAssertionsByProcess` |
| Spotlight load | CPU of `mds`, `mds_stores`, `mdworker*` processes |
| Startup items | `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `launchctl print gui/<uid>` non-Apple labels, `SMAppService`/Background Task Management items (investigate best available API; `sfltool dumpbtm` needs root — fall back to diffing what's readable). Snapshot on first run; alert on additions. |
| Failing launch jobs | non-zero last exit status in `launchctl list`, repeating |

## 5. UI

### 5.1 Menu bar icon
- Custom icon: a solid 15 pt rounded square in the menu bar's text color (black on light, white on dark) with a heartbeat cut out of it, so the menu bar shows through the line. Static, not animated.
- Health dot on its bottom-right corner: green when all good, amber or red when any vital/alert is.
- Optional: right-click → Rescan / Settings / Quit.

### 5.2 Panel (~360 pt wide, native look, light/dark, vibrancy)
Two sections only.

**Vitals** — compact rows: color dot · name · value · one-line context. Examples:
- 🟢 Memory · 21.6 of 32 GB · Plenty of room.
- 🟠 Memory · Swap 6.1 GB · Your Mac is moving memory to the disk right now, so things feel sluggish.
- 🟢 CPU · 15% busy
- 🟠 Battery · 54% · 77% health, 1,450 cycles. Can slow your Mac near empty.
- 🟢 Disk · 522 GB free
- 🟠 Uptime · 16 days · A restart clears built-up slowdowns.
- 🟢 Temperature · Normal

Click a row to expand slightly (secondary details, e.g. compressed memory, top 3 contributors). No separate "what's heavy" section — heaviness surfaces through alerts.

**Alerts** — cards sorted by severity. Each card:
- Icon + one-sentence title ("Comet is using most of your memory").
- One-line why/impact ("~10 GB across 25 tabs. Restarting it frees memory; tabs reopen.").
- Primary button (the fix) + overflow menu: Snooze 1 day / 1 week / Acknowledge ("I know") / Ignore this app.
- Empty state: "All good. Nothing needs you." 

Footer: "Copy for Claude" (copies a markdown snapshot of vitals + alerts + top processes with numbers), Rescan, Settings gear.

### 5.3 Settings window
- General: launch at login, notifications on/off, quiet hours.
- Vitals shown and alert types enabled (checkbox per item). Battery vital and battery alerts are off by default. Hidden vitals/disabled alerts don't affect the menu bar icon.
- Thresholds (sensible defaults below, editable).
- Cleanup scan roots (default `~/Code`), "untouched for N days" (default 90).
- Ignore list (apps/processes never to alert on, e.g. long builds).
- MCP: status, copy `claude mcp add` command, copy Claude app config JSON.
- About: the app's own CPU/RAM.

## 6. Color rules (defaults)

| Vital | Green | Amber | Red |
|---|---|---|---|
| Memory | pressure normal and not actively swapping (leftover swap is noted, not alarmed: it lingers for hours after a squeeze or a wake from hibernation) | pressure warn, ≥ 100 MB written to swap in the last 5 min, or memory ≥ 90% used with swap ≥ 2 GB | pressure critical, or pressure warn with swap > 6 GB |
| CPU | < 60% sustained | 60–85% for 5 min | > 85% for 5 min |
| Battery | health ≥ 85% and charge ≥ 20% | health < 85% or condition ≠ Normal, or charge 10–20% on battery | charge < 10% on battery |
| Disk | > 15% free | 5–15% free | < 5% free |
| Uptime | < 7 days | 7–21 days | > 21 days |
| Temperature | nominal/fair | serious | critical |

Acknowledged issues keep their vital color but stop generating notifications.

## 7. Alert catalog (v1)

Each alert has: `id`, `kind`, `subject`, `severity`, `title`, `detail`, `fixes[]`, `notify: bool`.

| Kind | Trigger (default) | Fix button(s) | Notify |
|---|---|---|---|
| `memory_hog` | memory amber/red, and an app group is > 6 GB or the top contributor (never while memory is green — a big app with room to spare isn't a problem). Title states its share in words, e.g. "about a fifth of your memory" | Restart app · Quit app | yes if memory red |
| `runaway_process` | process > 50% CPU for 10 min (not in ignore list) | Restart app · Force quit | yes |
| `memory_pressure` | memory red for 2 min | Show top contributors (expands) | yes |
| `uptime` | > 14 days | Restart Mac (with confirm, saves nothing for you — warn) · Remind me tonight | once/day |
| `low_battery_degraded` | on battery, charge < 15%, battery condition ≠ Normal | — (info: "Plug in soon — your battery slows the Mac near empty") | yes |
| `battery_service` | condition Service Recommended / health < 80% | Acknowledge · Open Apple battery support | once, then ack-able |
| `new_startup_item` | new LaunchAgent/Daemon/login/background item since last snapshot | Remove · Keep | yes |
| `failing_service` | launch job repeatedly exiting non-zero | Remove · Ignore | no |
| `junk_cleanup` | reclaimable > 5 GB across: Trash, known-safe caches (Spotify, browsers, npm, pip, Homebrew, Xcode DerivedData, Cypress, electron), `node_modules` in scan roots untouched ≥ 90 days | Clear (shows total + breakdown in confirm) | no (panel only) |
| `spotlight_heavy` | Spotlight processes > 20% CPU for 15 min | Exclude dev folders (`node_modules`, `~/.npm`, `~/.cache`) · Open Spotlight settings | no |
| `sleep_blocked` | on battery, an app preventing sleep > 30 min | Quit app · Ignore | no |
| `low_disk` | disk red | Run cleanup · Open Storage settings | yes |
| `thermal` | thermal serious/critical | Show top CPU apps | yes |

**Confirmations:** only for actions that delete files or remove startup items (one native sheet listing exactly what goes). Quit/restart app: no confirm. Restart Mac: confirm.

**Removal behavior:** move files to Trash (not hard delete) except caches/`node_modules`, which are deleted (regenerable). Startup item removal = `launchctl bootout` + move plist to Trash; for `SMAppService`-registered items that can't be removed programmatically, deep-link to System Settings > Login Items and say so.

## 8. Notifications

- `UNUserNotificationCenter`, category per alert kind, with the primary fix as a notification action button plus "Snooze".
- Rate limit: same alert subject at most once per 6 h; respect snooze/ack/quiet hours.
- Clicking the notification body opens the panel scrolled to that alert.

## 9. MCP server (v1)

Server name: `mac-monitor`. **Read-only by decision:** the MCP is for understanding an alert that isn't a simple one-button fix. Claude explains and recommends; the user (or Claude with its own tools, on the user's OK) carries out the fix. Pressing the app's fix buttons over MCP wouldn't save meaningful effort.

| Tool | Purpose |
|---|---|
| `get_vitals` | All vitals with value, color, context line, details, whether shown in the panel, plus the raw system numbers behind them |
| `list_alerts` | All alerts incl. id, severity, detail, the fix buttons the app offers, and status (active / snoozed / acknowledged / hidden in Settings) |
| `get_top_processes` | Top 10 apps by CPU and by memory, helper processes grouped under each app, with raw numbers, PIDs, bundle paths |
| `get_startup_items` | (with Milestone 3) All non-Apple startup/background items + which are new |
| `get_cleanup_candidates` | (with Milestone 3) Reclaimable items with sizes |

Data is from the app's latest sample (every 30 s, every 4 s while the panel is open); each response says how many seconds old it is.

Setup: `claude mcp add mac-monitor -- "/Applications/Mac Monitor.app/Contents/MacOS/macmon-mcp"` for Claude Code, or the equivalent entry in the Claude app's `claude_desktop_config.json`.

## 10. Companion Claude skill

A separate Claude skill ("mac-checkup") lets John start a chat, invoke it, and have Claude pull `list_alerts` + `get_vitals`, explain what's going on in plain language, and recommend fixes. Not part of this repo's build, but the MCP tool names above are the contract — don't rename them without updating the skill.

## 11. Milestones

1. **Skeleton**: menu bar app, launch at login, engine with memory/CPU/battery/disk/uptime/thermal collectors, Vitals UI with colors.
2. **Alerts + fixes**: process grouping, alert evaluators, FixAction registry, alert cards, snooze/ack, confirm sheets.
3. **Scans**: startup item snapshot/diff, cleanup scanner, Spotlight + sleep-blocker detection.
4. **Notifications**: actionable notifications, rate limiting, quiet hours.
5. **MCP**: state files written by the app, read-only `macmon-mcp` stdio server, Settings setup panel, "Copy for Claude".
6. **Polish**: Settings window, thresholds, ignore list, self-usage readout, icon states.

## 12. Acceptance criteria

- Icon shows amber/red dot within one sample cycle of a vital crossing a threshold.
- Starting a CPU burner (`yes > /dev/null`) produces a `runaway_process` alert + notification after the configured window, and "Force quit" kills it.
- Installing any app that adds a LaunchAgent produces a `new_startup_item` alert; "Remove" unloads it and moves the plist to Trash.
- Junk cleanup confirm sheet lists every path and total size; after clearing, the alert disappears on rescan.
- Snoozed/acknowledged alerts don't notify; ack persists across relaunch.
- `claude mcp add …` works; from Claude Code, `list_alerts` and `get_vitals` match what the panel shows.
- Mac Monitor's own average CPU < 1% over an hour with panel closed.

## 13. Open questions for the builder

- Best available API on macOS 27 for enumerating Background Task Management (Login Items "Allow in background") entries without root.
- Reliable programmatic Spotlight exclusion on macOS 27 (Privacy list) — if not possible without root/UI, fall back to deep link + `.metadata_never_index` where it still works.
- Whether battery "condition" is exposed cleanly via `IOPSCopyPowerSourcesInfo` or needs IOKit registry parsing.
