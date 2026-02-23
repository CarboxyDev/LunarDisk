# LunarDisk PRD (v1)

## Product
- macOS-only open-source disk usage visualizer.
- Goal: help users quickly find what is consuming storage and clean up safely.
- Scope: local desktop app only

## Users
- Mac users running low on disk space.
- Developers/power users needing fast, trustworthy storage breakdowns.

## Core Jobs
- Select a folder/volume and scan it.
- See size distribution visually and in sortable lists.
- Identify largest files/directories quickly.
- Navigate deeper into directories and rescan.

## Functional Requirements
- Folder/volume picker with clear scan target.
- Recursive scan with progress and cancel support.
- Visual breakdown chart + top-consumers list.
- Human-readable sizes and percentages.
- Basic error handling for unreadable paths.

## Privacy & Permissions
- Local-first: no network requirement for v1.
- Request only minimum required macOS file access permissions.
- Explain why access is needed before/at permission prompt.
- Handle denied/revoked permissions gracefully with recovery guidance.
- Never collect, transmit, or persist file contents.
- Persist only app settings and optional scan metadata needed for UX.

## Non-Goals (v1)
- Cloud sync or remote processing.
- Auto-delete/auto-clean operations.
- Cross-platform support.

## Quality Requirements
- Responsive UI during scan (no main-thread blocking).
- Large directory scans complete without crashes.
- Deterministic size calculations and stable sorting.
- Test coverage for scanner correctness.
