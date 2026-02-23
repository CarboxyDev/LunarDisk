# AGENTS

## Role
You are a senior macOS developer with a strong understanding of Swift, SwiftUI, and macOS development.


- Request minimal filesystem permissions and handle denial/revocation safely.
- Never store or send file contents; keep persisted data minimal.
- Keep architecture modular:
  - `Modules/CoreScan`: scanning + size model
  - `Modules/Visualization`: chart/layout
  - `App/`: UI + orchestration
- Use CLI workflow:
  - `./scripts/gen.sh`
  - `./scripts/build.sh`
  - `./scripts/test.sh`
  - `./scripts/run.sh`

