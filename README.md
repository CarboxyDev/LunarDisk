# LunarDisk

<p align="center">
  <img src="assets/brand/lunardisk-icon.png" alt="LunarDisk icon" width="140" />
</p>

LunarDisk is a macOS-only, open-source disk usage visualizer focused on helping users find and clean large storage consumers safely.

## About This Project

LunarDisk helps macOS users understand what is taking space on their machine and act on it safely.

- Built for: anyone running low on disk space, especially users who want a clear visual breakdown before deleting anything.
- How it works: choose a folder or volume, run a recursive scan, inspect the size breakdown, then drill into large directories and files.
- Open-source focus: readable Swift/SwiftUI architecture, modular scanning and visualization layers, and contributor-friendly scripts.
- Privacy model: local-first with least-privilege file access; no file-content collection or transmission.

## Install

- Latest release: [GitHub Releases](https://github.com/CarboxyDev/Lunardisk/releases)

## Workflow

- Prereq: Xcode command-line tools + XcodeGen (`brew install xcodegen`).
- Generate project: `./scripts/gen.sh`
- Build: `./scripts/build.sh`
- Test: `./scripts/test.sh`
- Run: `./scripts/run.sh`

## Product Preview

![Scan View Overview](assets/screenshots/scan-view-overview.png)
![Scan View Insights](assets/screenshots/scan-view-insights.png)
![Scan View Actions](assets/screenshots/scan-view-actions.png)
