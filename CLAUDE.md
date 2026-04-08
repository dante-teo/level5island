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

**Three targets** (see `Package.swift`):

| Target | Type | Path | Purpose |
|--------|------|------|---------|
| `Level5IslandCore` | Library | `Sources/Level5IslandCore/` | Pure business logic: models, state reduction, event normalization |
| `Level5Island` | Executable | `Sources/Level5Island/` | App layer: UI, window management, settings, hook installation |
| `level5island-bridge` | Executable | `Sources/Level5IslandBridge/` | Native CLI hook binary (~86KB): terminal detection, socket forwarding |

**Data flow** (unidirectional, Redux-like):
```
AI Tool hook → level5island-bridge → Unix socket → HookServer
  → HookEvent parsed → reduceEvent() → [SideEffect]
    → AppState executes effects → SwiftUI observes changes
```

### Key patterns

- **Pure reducer**: `reduceEvent(sessions:event:maxHistory:)` is a pure function that returns `[SideEffect]` — all state changes go through it
- **State machine**: `AgentStatus.canTransition(to:)` validates all status transitions; the reducer gates every `session.status = X` assignment through it
- **Side effects**: Returned from the reducer, executed by `AppState` (sounds, process monitoring, UI triggers)
- **Intervention caching**: `InterventionCache` (30s TTL) auto-replays answers when Claude Code retries the same `AskUserQuestion`
- **Interrupt detection**: `InterruptWatcher` monitors session JSONL files via `DispatchSource` as a fallback when the hook doesn't fire on Ctrl+C
- **Claude Code only**: single CLI source with direct PascalCase event names

### Key files

- `SessionSnapshot.swift` — Core state model + `reduceEvent()` reducer
- `Models.swift` — `HookEvent`, `AgentStatus` (with `canTransition`/`needsAttention`/`isActive`), `QuestionPayload`
- `AppState.swift` — Observable main state, session lifecycle, effect execution
- `ConfigInstaller.swift` — Auto-installs Claude Code hooks into `~/.claude/settings.json`
- `DesignTokens.swift` — `Design` enum: colors, typography, spacing, `timeAgo()` for UI
- `NotchPanelView.swift` — Main panel UI (compact + expanded modes)
- `QuestionFormView.swift` — Question form: multi-select, secret input, markdown, "other" option
- `ChatMessageTextFormatter.swift` — Shared markdown cache with LRU eviction
- `MarkdownText.swift` — Inline markdown rendering view
- `InterventionCache.swift` — TTL cache for repeated question auto-replay
- `InterruptWatcher.swift` — JSONL file watcher for interrupt detection
- `SessionHoverCard.swift` — Hover preview card for compact bar sessions
- `PanelWindowController.swift` — Window positioning, visibility, notch detection
- `TerminalActivator.swift` — Jump-to-terminal: window focus + tab switching
- `Settings.swift` — `SettingsManager` singleton, `SettingsKey` enum, UserDefaults-backed

## Conventions

- macOS 14.0+ (Sonoma), Swift 5.9+
- **Design tokens**: All UI colors/fonts/spacing go through `Design` enum in `DesignTokens.swift` — no hardcoded `Color(red:green:blue:)` in views. Use `Design.toolColor()` for tool-specific colors, `Design.headline/body/caption()` for SF Pro, `Design.mono()` for SF Mono (code content only). Panel forces `.darkAqua` appearance so semantic colors (`.primary`, `.secondary`, `.tertiary`) always resolve to white-on-black.
- Bilingual UI strings in `L10n.swift` (English + Chinese)
- Logging via `os.log` with subsystem `com.level5island`
- Bundle ID: `com.level5island` (see `Info.plist`)
- App icon compiled from `Assets.xcassets` + `AppIcon.icon` via `xcrun actool`
- Resources (sounds) in `Sources/Level5Island/Resources/`
