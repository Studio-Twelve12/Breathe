# Breathe

A native macOS menu-bar app that monitors processor and memory usage, surfaces
the most active apps, and lets you gracefully quit resource-heavy applications
you own.

**A Studio 12 product.** Originally developed by Lucid (v1–v4); Lucid was
acquired by Studio 12, and Breathe is now maintained by Studio 12 starting at
v1.0.

**Requirements:** macOS 13+ (Ventura) · Apple Silicon or Intel

---

## Build & run

1. Open `Breathe.xcodeproj` in Xcode.
2. Select the **Breathe** scheme and press **⌘R**.

A wind icon appears in the menu bar; click it for the 380 pt monitoring panel.
Breathe runs as a menu-bar agent (no Dock icon) and ships with App Sandbox
disabled so it can read system-wide metrics and signal processes.

## How it works

| File | Role |
|---|---|
| `BreatheApp.swift` | App entry; `MenuBarExtra` host |
| `MenuBarView.swift` | The panel UI (metric bars + process list) |
| `SystemMonitor.swift` | Polls CPU/RAM/processes every 5s via `top`/`vm_stat`/`ps` |
| `ProcessInfo.swift` | `AppProcess` model |

## Releasing a new version (so upgrades are easy)

1. Bump `MARKETING_VERSION` in the target's build settings.
2. Archive: **Product → Archive**, then export a signed `.app`.
3. Zip it: `zip -r Breathe-<version>.zip Breathe.app`
4. Tag and push: `git tag v<version> && git push origin v<version>`
5. Create a GitHub Release for that tag and attach the zip.

## Lineage

- **v1–v4** — developed by Lucid
- **v1.0 (reboot)** — Studio 12, following the acquisition

---
*Maintained by Studio 12.*
