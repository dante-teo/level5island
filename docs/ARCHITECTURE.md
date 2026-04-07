# Architecture

## System Overview

```
┌─────────────────┐     ┌─────────────────────┐     ┌──────────────────┐
│  AI CLI Tool     │────▶│  level5island-bridge  │────▶│  CodeIsland.app  │
│  (hook trigger)  │     │  (native binary)     │     │  (HookServer)    │
└─────────────────┘     └─────────────────────┘     └──────────────────┘
                              │                            │
                         Terminal detection          Unix socket IPC
                         JSON serialization     /tmp/level5island-<uid>.sock
```

## Targets

### CodeIslandCore (Library)
Pure business logic with no UI or system dependencies beyond Foundation.

- **SessionSnapshot** — Core state model. Contains all session data: status, tool history, subagents, terminal info, chat messages. The `reduceEvent()` method is the single entry point for all state mutations.
- **Models** — `HookEvent` (parsed from JSON), `AgentStatus` enum, `ToolHistoryEntry`, `ChatMessage`, `SubagentState`, `QuestionPayload`
- **EventNormalizer** — Maps tool-specific event names to canonical names. Each CLI tool uses a different hook format (claude, nested, flat, copilot), and this normalizer unifies them.
- **ChatMessageTextFormatter** — Formats chat messages for compact display

### CodeIsland (App)
SwiftUI application layer. Observable state, UI, system integration.

**State & Lifecycle:**
- **AppState** — `@Observable` main state object. Owns session dictionary (`[String: SessionSnapshot]`), routes events through `reduceEvent()`, executes side effects (sounds, process monitoring), manages session cleanup timers.
- **AppDelegate** — App lifecycle. Starts HookServer, initializes recovery timers, handles relaunch.
- **HookServer** — Listens on Unix socket, accepts connections, parses JSON into `HookEvent`, dispatches to AppState.

**Hook Installation:**
- **ConfigInstaller** — Detects which CLI tools are installed and writes hook entries into their config files. Each tool has a different config format and location. Handles version tracking and auto-repair.

**Window Management:**
- **PanelWindowController** — Creates and positions the notch panel window. Handles show/hide/collapse, mouse tracking, fullscreen detection, multi-display support.
- **ScreenDetector** — Identifies notch displays vs external monitors for correct panel positioning.

**Terminal Integration:**
- **TerminalActivator** — Jump-to-terminal: activates the correct app, switches to the right tab/window. Supports iTerm2 (AppleScript session targeting), Kitty (socket commands), tmux panes, VS Code, JetBrains IDEs.
- **TerminalVisibilityDetector** — Determines if a specific terminal tab is currently visible to the user (for smart suppress).

**Settings:**
- **SettingsManager** — Singleton, UserDefaults-backed. `SettingsKey` enum defines all keys, `SettingsDefaults` provides defaults.

**UI:**
- **NotchPanelView** — Main panel with compact (single row) and expanded (detail) modes. Renders session list, tool history, chat preview, permission/question UI.
- **SettingsView** — 7-tab settings window.
- Tool-specific views: `CursorView`, `CopilotView`, `GeminiView`, `QoderView`, `DroidView`, `BuddyView`, `DexView`, `OpenCodeView`
- **PixelCharacterView** / **MascotView** — Pixel-art mascot rendering with animation states.

### level5island-bridge (CLI Binary)
Lightweight (~86KB) native binary invoked by CLI tool hooks.

1. Reads JSON event from stdin
2. Detects terminal environment (bundle ID, TERM_PROGRAM, tty, tmux, iTerm session)
3. Enriches the event with terminal metadata
4. Sends enriched JSON over Unix socket to CodeIsland.app

## Data Flow (Unidirectional)

```
HookEvent (from socket)
  │
  ▼
SessionSnapshot.reduceEvent(event, source)  ← pure function
  │
  ├── mutates SessionSnapshot in place
  └── returns [SideEffect]
        │
        ▼
AppState.executeSideEffects()
  │
  ├── PlaySound(.approval)
  ├── StartProcessMonitor(pid)
  ├── TriggerUIUpdate
  └── ...
```

The reducer pattern ensures all state transitions are predictable and testable. Side effects are declarative — the reducer says *what* should happen, AppState decides *how*.

## Event System

### Hook Formats
Different CLI tools emit events in different formats:
- **claude**: Native Claude Code hooks (13 event types)
- **nested**: Cursor/Gemini/Qoder/Factory/CodeBuddy format
- **flat**: Codex format
- **copilot**: GitHub Copilot format

### Key Events
`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `SessionStart`, `SessionEnd`, `Notification`, `SubagentStart`, `SubagentStop`, `AssistantResponse`

### Session Identity
Sessions are keyed by `sessionId` (from the hook event). Multiple sessions can be active simultaneously. The panel rotates through active sessions or the user can pin one.

## IPC Protocol

- **Transport**: Unix domain socket at `/tmp/level5island-<uid>.sock`
- **Format**: Newline-delimited JSON
- **Direction**: Bridge → App (events), App → Bridge (responses for permission/question)
