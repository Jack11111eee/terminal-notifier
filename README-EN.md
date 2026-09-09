# Terminal Notifier

> A pixel cat that lives in your macOS menu bar and reminds you when it's time to check your terminal.

English | [简体中文](README.md)

## What is this?

When you're using Claude Code or Codex, do you often switch to another app and forget that they're waiting for you to confirm an action?

Terminal Notifier watches the Terminal.app Dock badge by default, and can tell "needs confirmation" apart from "conversation complete" through Claude Code and Codex hooks. When something needs you, the pixel cat appears in the center of the screen with a compact reminder — without stealing keyboard focus from the app you're in.

## Demo

1. The pixel cat quietly lives in the menu bar 🐱
2. Terminal.app shows a Dock badge, or a Claude Code / Codex hook fires an event
3. The cat and the reminder panel appear, without interrupting your typing in the current app
4. You can choose "Close", "Later", or "Open source"; you can also decide whether clicking the cat opens the source
5. Unanswered reminders can auto-collapse to the menu bar and stand by again after the cooldown

## Installation

### Download

Grab the latest `.zip` from [GitHub Releases](https://github.com/Jack11111eee/terminal-notifier/releases), unzip it, and drag `Terminal Notifier.app` into your `Applications` folder.

### Build from source

**Requirements:**
- macOS 13 Ventura or later
- An Apple Silicon Mac
- Xcode or the Xcode Command Line Tools (`xcode-select --install`)
- A code-signing certificate named `TerminalNotifierDev` in your login keychain, which keeps the Accessibility permission stable across rebuilds

```bash
git clone https://github.com/Jack11111eee/terminal-notifier.git
cd terminal-notifier
./build.sh
open "build/Terminal Notifier.app"
```

To also copy the app to `/Applications` after building:

```bash
INSTALL=1 ./build.sh
```

### Build a local preview DMG

To produce an Apple Silicon DMG for a local install check, without installing or releasing the app:

```bash
bash package-dmg.sh
```

The DMG and its SHA-256 checksum are written to `build/`. The script signs ad-hoc by default and does not notarize; set `SIGN_IDENTITY` to use an existing signing identity. When built with the macOS 26 SDK and run on macOS 26, Liquid Glass is enabled; other builds or system versions fall back to native controls and materials.

### Regression tests

With full Xcode installed and selected as the active developer tool, run `bash test.sh`. The tests use temporary config files and in-process preferences — they don't touch your real Claude/Codex config, don't launch the app, and don't request system permissions.

In a macOS graphical session you can run `TN_RUN_UI_TESTS=1 bash test.sh` to additionally cover window scaling, long-message button layout, reminder-panel focus, and animation completion with Reduce Motion enabled.

The settings window uses the modern Liquid Glass layout when built on macOS 26 with Swift 6.2 or later, and the legacy native-material layout otherwise. Use `bash dev-preview.sh settings modern` and `bash dev-preview.sh settings compatible` to preview both modes on the same Mac while developing.

GitHub Actions builds the app, verifies the ad-hoc signature, and runs these regression tests on PRs targeting `main` and on pushes to `main`. CI does not install the app, does not use a formal signing certificate, and does not publish installers automatically.

## Features

- **Zero-permission badge detection**: by default it only reads the Terminal Dock badge — no Accessibility or screen-recording permission needed
- **Claude Code / Codex state detection** (optional): tells "needs confirmation" from "conversation complete" directly via hooks, without relying on terminal bells
- **Claude frontmost multi-window attribution** (optional enhancement): when Terminal.app is frontmost, Claude hook events from a non-topmost Terminal window still trigger reminders
- **Compact reminders**: the reminder panel never steals keyboard focus, and offers three distinct actions — "Close", "Later", and "Open source"
- **Fullscreen friendly**: the cat can pop up even while you're watching video or coding fullscreen
- **Do not disturb**: set a window (say 22:00–08:00) and the cat keeps quiet
- **Cooldown**: adjustable (5–120 s) so the cat doesn't spam you
- **Reminder history**: browse and search past reminders by date; opening a record jumps to the matching Terminal or Codex source
- **Tiered sounds**: confirmation-needed reminders play a more attention-grabbing sound, ordinary completion reminders a gentler one — your ears can tell them apart
- **Self-check & repair**: one click in the menu bar checks permissions and hook status, and failed items can be repaired in place
- **Focus mode integration**: when a macOS Focus is on, reminders go silent, leaving only the menu-bar red dot and the history
- **Accessibility aware**: follows the system appearance, Increase Contrast, Reduce Transparency, and Reduce Motion settings
- **English & Chinese**: picked automatically from the system language, or set manually
- **Pixel art**: a proper pixel-art cat

## Claude Code state detection (optional)

The default badge detection only knows that "something happened in the terminal". Turn on **Detect Claude Code state** in Settings, and the app reads conversation state directly through official Claude Code hooks, distinguishing two kinds of events:

- **Needs confirmation**: Claude is waiting for you to approve an action (`Notification` / `permission_prompt`)
- **Conversation complete**: Claude finished a turn (`Stop`)

When you enable it, the app **safely merges** its hooks into `~/.claude/settings.json` (all your existing hooks are preserved, and a `settings.json.tn-backup-<timestamp>` backup is written before every change); turning it off removes them. When Terminal is in the background, you get the reminder right away; when Terminal is frontmost, reminders stay suppressed by default so the window you're already looking at isn't disturbed.

**Frontmost multi-window attribution:** to also catch Claude events coming from a non-topmost Terminal window while Terminal.app is frontmost, additionally turn on "Locate the source window" in Settings. This enhancement requests the Accessibility permission and may request permission to automate Terminal; locating the source window for "Open source" or cat clicks also relies on it. When it's off or unauthorized, the behavior falls back to zero-Accessibility: remind when Terminal is backgrounded, suppress when frontmost.

**Limitations:** pressing Esc to interrupt triggers no Claude Code hook, so interrupts can't be detected, and this feature doesn't handle typing idleness. The automatic merge normalizes the formatting and key order of settings.json (a backup is kept).

## Codex state detection (optional)

Turn on **Detect Codex state** in Settings, and the app captures two kinds of events through Codex lifecycle hooks:

- **Needs confirmation**: Codex is waiting for you to approve an action (`PermissionRequest`)
- **Conversation complete**: Codex finished a turn (`Stop`)

When enabled, the app **safely merges** its managed hooks into `~/.codex/hooks.json` (all your existing hooks are preserved, and a `hooks.json.tn-backup-<timestamp>` backup is written before every change); turning it off removes them. Just like badge detection, reminders pop **only when Codex is not frontmost**. You can turn off `PermissionRequest` approval reminders separately and keep only `Stop` completion reminders.

**Hooks must be trusted:** after enabling or changing Codex hooks, quit and reopen Codex so the hooks reload. Then open Codex **Settings → Hooks** and trust `Terminal Notifier: Codex approval reminder` (`PermissionRequest`, if enabled) and `Terminal Notifier: Codex completion reminder` (`Stop`). Until trusted, Codex skips these hooks and Terminal Notifier won't receive the reminders.

**auto-review:** Codex's `auto-review` flow can still emit `PermissionRequest` hooks, so you may see a "needs confirmation" reminder even when Codex completes the review automatically. If you only want completion reminders, turn off approval request reminders in Settings.

**Limitations:** Codex hooks are a user-level config and can be picked up at once by the Codex App, CLI, or IDE Extension on the same machine; the specific Codex entry point isn't distinguished, and the Codex App's internal live state isn't read. To check whether a hook ran, look at `~/Library/Application Support/TerminalNotifier/codex-hook.log`.

## Settings

Click the menu-bar cat → **Settings** to adjust:

| Setting | Description | Default |
|--------|------|--------|
| Enable notifications | Master switch for all reminders | On |
| Detect Claude Code state | Distinguish "needs confirmation / conversation complete" via hooks | Off |
| Locate the source window | Catch Claude events from non-topmost Terminal windows; requires the Accessibility permission | Off |
| Detect Codex state | Distinguish "needs confirmation / conversation complete" via Codex hooks | Off |
| Approval request reminders | Whether to react to `PermissionRequest`; completion reminders are unaffected | On |
| Launch at login | Start automatically after you sign in | Off |
| Language | Chinese / English / System | System |
| Play sound | Play a sound with each reminder | On |
| Minimum reminder interval | Shortest gap between two reminders | 10 s |
| Scheduled quiet hours | Pause reminders during a set time window | Off |
| Click the cat to open the source | When on, clicking the cat switches to Terminal / Codex; "Close" and "Later" never switch apps | Off |

## Changelog

### v1.3.0 (Unreleased)
- Settings, reminder history, and self-check moved into native, resizable windows; macOS 26 gets Liquid Glass, older systems fall back to native materials.
- Reminders were redesigned as compact panels that don't steal keyboard focus, with separate "Close" / "Later" / "Open source" actions, and they adapt to the system's accessibility display settings.
- Reminder history gained search, date grouping, message copy, and opening Terminal / Codex by source.
- Fixed the cleanup logic for mixed hook groups; user hooks and group settings in the same group now survive install, update, and uninstall.
- Fixed the state machine getting stuck after quiet hours, Focus mode, or disabled notifications intercepted a display; intercepted reminders are kept as pending records.
- Claude/Codex hook reminders are now queued in receive order; new events arriving while the current reminder is showing or animating in/out no longer get lost or overwrite it; after collapsing, they're handled one by one per the cooldown.
- Claude Code state detection gained Terminal-frontmost multi-window attribution: events from non-topmost Terminal windows also trigger reminders, and, with it enabled, you can jump to the source window.
- Frontmost multi-window attribution became its own advanced toggle; background Claude hook reminders no longer request the Accessibility permission automatically.
- Claude hook markers switched to JSON, carrying event type, source, TTY, and timestamp; old-style empty markers are still accepted.
- Added reminder lifecycle management: unanswered reminders auto-collapse into a menu-bar red dot after a timeout (60 s by default, can be disabled), and the bubble gained a "Later" button to snooze and pop again later.
- Added "Pending reminders" in the menu bar: suspended events can be re-opened or cleared with one click.
- Added click-through in reminder history: click a record to jump straight to the terminal window, plus today's reminder stats.
- Added tiered sounds: confirmation-needed reminders use a more attention-grabbing sound, ordinary reminders keep the gentler one.
- Added "Self-check & repair" in the menu bar: one click to diagnose the Accessibility permission, Claude/Codex hooks, and config backups, with failed items repairable in place.
- Added Focus integration: reminders go silent while a system Focus is on, leaving only the menu-bar red dot and history.
- Codex state detection can now turn off `PermissionRequest` approval reminders alone while keeping `Stop` completion reminders.

### v1.2.1
- **Fixed language switching not working**: the Settings window used to read only the system language and ignore your choice, disagreeing with the reminder speech logic; both now use one shared decision — the choice applies immediately, and Settings and reminder language always match.
- Renamed the pet option to "Orange Cat" in Settings.
- The cooldown went from a slider to a dropdown (5/10/15/30/60/120 seconds).

### v1.2.0
- **Official pixel cat art**: the previously code-drawn placeholder cat was replaced with hand-drawn PNG pixel cats; the menu-bar cat's normal / reminding / paused states each have a dedicated look (orange / red / gray).
- Pixel rendering now disables anti-aliasing and aligns to whole pixels, so it stays crisp when scaled.

### v1.1.0
- Added **Claude Code state detection** (optional): distinguishes "needs confirmation" from "conversation complete" via Claude Code hooks instead of terminal bells; enabling it safely merges hooks into `~/.claude/settings.json` (with a backup), disabling removes them.

### v1.0.0
- First stable release: menu-bar pixel cat + Terminal Dock badge detection + drop animation + settings / history / sound.

## Tech stack

Swift + AppKit + SwiftUI, with no third-party frameworks.

## Documentation

- [User guide](docs/USER-GUIDE.md) (Chinese)
- [Architecture](docs/ARCHITECTURE.md) (Chinese)

## License

MIT License

## Acknowledgments

Inspired by the pet-companion plugins in programming IDEs, and by the developers who always manage to miss the Dock's red dot.
