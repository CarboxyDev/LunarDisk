# Lunardisk

Lunardisk is a macOS-only open-source disk usage analyzer inspired by DaisyDisk.

## Repository layout

- `App/`: macOS SwiftUI application target.
- `Modules/CoreScan/`: file system scanning engine and shared file tree model.
- `Modules/Visualization/`: sunburst layout and chart rendering.
- `Modules/LunardiskAI/`: local heuristic analysis layer (AI-ready interface for later providers).
- `scripts/`: terminal-first workflows for generate/build/test/run/clean.
- `project.yml`: source-of-truth Xcode project configuration for XcodeGen.

## Prerequisites

- Xcode (already installed) and command-line tools:
  - `xcodebuild -version`
- XcodeGen:
  - `brew install xcodegen`

## Terminal workflow

- Generate project:
  - `./scripts/gen.sh`
- Build app:
  - `./scripts/build.sh`
- Run app:
  - `./scripts/run.sh`
- Reset local app state (default scope: onboarding):
  - `./scripts/reset-state.sh`
  - `./scripts/reset-state.sh onboarding`
  - `./scripts/reset-state.sh all`
  - `RESET_STATE=onboarding ./scripts/run.sh`
  - `LUNARDISK_RESET_STATE=onboarding ./scripts/run.sh`
  - launch arg for direct app runs: `--reset-state=onboarding` (or `--reset-state-all`)
- Run all tests:
  - `./scripts/test.sh`
- Clean generated artifacts:
  - `./scripts/clean.sh`

## Notes

- The generated `Lunardisk.xcodeproj` is ignored and can always be recreated from `project.yml`.
- v1 is local-only and has no backend/API dependency.
