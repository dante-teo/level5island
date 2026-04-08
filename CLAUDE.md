# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Level5Island is a native macOS menu bar app (Swift/SwiftUI) that displays real-time status of Claude Code sessions in the MacBook notch. It connects via Unix socket IPC (`/tmp/level5island-<uid>.sock`) to receive hook events from Claude Code.

## Build & Run

```bash
# Debug build + launch
swift build && open .build/debug/Level5Island.app

# Release (universal binary: ARM64 + x86_64)
./build.sh
open .build/release/Level5Island.app

# Run tests
swift test

# Run a single test class
swift test --filter SessionSnapshotTitleTests

# Run a single test method
swift test --filter SessionSnapshotTitleTests/testClaudeTitle
```

No external dependencies — uses only SPM with system frameworks (SwiftUI, AppKit, Foundation, CoreServices).

## Architecture

Three SPM targets: `Level5IslandCore` (pure logic library), `Level5Island` (SwiftUI app), and `level5island-bridge` (lightweight CLI hook binary). Unidirectional data flow via a pure reducer that returns declarative side effects.

For full details — targets, data flow, event system, IPC protocol — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Quick reference

- `SessionSnapshot.swift` — Core state model + `reduceEvent()` pure reducer
- `Models.swift` — `HookEvent`, `AgentStatus` (state machine with `canTransition`), `QuestionPayload`
- `AppState.swift` — Observable main state, session lifecycle, effect execution
- `ConfigInstaller.swift` — Auto-installs Claude Code hooks into `~/.claude/settings.json`
- `DesignTokens.swift` — `Design` enum: colors, typography, spacing, `timeAgo()` for UI
- `NotchPanelView.swift` — Main panel UI (compact + expanded modes)

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Targets, data flow, event system, IPC protocol
- [docs/PRODUCT.md](docs/PRODUCT.md) — Features, supported tools, settings, distribution
- [docs/DESIGN.md](docs/DESIGN.md) — Visual identity, panel modes, mascot system, layout decisions

> **Scope of this file:** Build commands, architecture summary, coding conventions, and pointers to detailed docs. For product features and supported tools, see PRODUCT.md. For visual design decisions, see DESIGN.md.

## Conventions

- macOS 14.0+ (Sonoma), Swift 5.9+
- **Design tokens**: All UI colors/fonts/spacing go through `Design` enum in `DesignTokens.swift` — no hardcoded `Color(red:green:blue:)` in views. Use `Design.toolColor()` for tool-specific colors, `Design.headline/body/caption()` for SF Pro, `Design.mono()` for SF Mono (code content only). Panel forces `.darkAqua` appearance so semantic colors (`.primary`, `.secondary`, `.tertiary`) always resolve to white-on-black.
- Bilingual UI strings in `L10n.swift` (English + Chinese)
- Logging via `os.log` with subsystem `com.level5island`
- Bundle ID: `com.level5island` (see `Info.plist`)
- App icon compiled from `Assets.xcassets` + `AppIcon.icon` via `xcrun actool`
- Resources (sounds) in `Sources/Level5Island/Resources/`
