# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CodeIsland is a native macOS menu bar app (Swift/SwiftUI) that displays real-time status of Claude Code sessions in the MacBook notch. It connects via Unix socket IPC (`/tmp/codeisland-<uid>.sock`) to receive hook events from Claude Code.

## Build & Run

```bash
# Debug build + launch
swift build && open .build/debug/CodeIsland.app

# Release (universal binary: ARM64 + x86_64)
./build.sh
open .build/release/CodeIsland.app

# Run tests
swift test

# Run a single test class
swift test --filter SessionSnapshotTitleTests

# Run a single test method
swift test --filter SessionSnapshotTitleTests/testClaudeTitle
```

No external dependencies — uses only SPM with system frameworks (SwiftUI, AppKit, Foundation, CoreServices).

## Architecture

**Three targets** (see `Package.swift`):

| Target | Type | Path | Purpose |
|--------|------|------|---------|
| `CodeIslandCore` | Library | `Sources/CodeIslandCore/` | Pure business logic: models, state reduction, event normalization |
| `CodeIsland` | Executable | `Sources/CodeIsland/` | App layer: UI, window management, settings, hook installation |
| `codeisland-bridge` | Executable | `Sources/CodeIslandBridge/` | Native CLI hook binary (~86KB): terminal detection, socket forwarding |

**Data flow** (unidirectional, Redux-like):
```
AI Tool hook → codeisland-bridge → Unix socket → HookServer
  → HookEvent parsed → SessionSnapshot.reduceEvent() → [SideEffect]
    → AppState executes effects → SwiftUI observes changes
```

### Key patterns

- **Pure reducer**: `SessionSnapshot.reduceEvent()` is a pure mutating function that returns `[SideEffect]` — all state changes go through it
- **Side effects**: Returned from the reducer, executed by `AppState` (sounds, process monitoring, UI triggers)
- **Claude Code only**: single CLI source with direct PascalCase event names

### Key files

- `SessionSnapshot.swift` — Core state model + `reduceEvent()` reducer
- `Models.swift` — `HookEvent`, `AgentStatus`, `ToolHistoryEntry`, `ChatMessage`
- `AppState.swift` — Observable main state, session lifecycle, effect execution
- `ConfigInstaller.swift` — Auto-installs Claude Code hooks into `~/.claude/settings.json`
- `NotchPanelView.swift` — Main panel UI (compact + expanded modes)
- `PanelWindowController.swift` — Window positioning, visibility, notch detection
- `TerminalActivator.swift` — Jump-to-terminal: window focus + tab switching
- `Settings.swift` — `SettingsManager` singleton, `SettingsKey` enum, UserDefaults-backed

## Conventions

- macOS 14.0+ (Sonoma), Swift 5.9+
- Bilingual UI strings in `L10n.swift` (English + Chinese)
- Logging via `os.log` with subsystem `com.codeisland`
- Bundle ID: `com.codeisland` (see `Info.plist`)
- App icon compiled from `Assets.xcassets` + `AppIcon.icon` via `xcrun actool`
- Resources (sounds) in `Sources/CodeIsland/Resources/`
