# Design

> **Scope:** Visual identity, panel modes, mascot system, color/status mapping, and layout decisions. For architecture and data flow, see [ARCHITECTURE.md](ARCHITECTURE.md). For product features and supported tools, see [PRODUCT.md](PRODUCT.md).

## Visual Identity

Level5Island uses a pixel-art aesthetic with 8-bit inspired visuals throughout:
- Each of the 9 AI tools has a unique animated pixel-art mascot
- Sound effects are 8-bit WAV files
- The panel uses a compact, information-dense layout suited to the notch area

## Panel Modes

### Compact Mode
Single-row display in the notch area showing:
- Active session count
- Current tool being used
- Agent status indicator
- Mascot animation reflecting current state

### Expanded Mode
Drops down from the notch when clicked/hovered, showing:
- Session list with status indicators
- Tool call history timeline
- Recent chat messages (last 3)
- Permission approval / question answering UI
- Subagent activity

## Mascot System

The mascot (`ClawdView`) is a pixel-art woman character rendered entirely via SwiftUI `Canvas` — no image assets:
- **Sleep** (`idle`): face bust, closed eyes, breathing puff, floating z's
- **Work** (`processing`/`running`/`compacting`): squinting eyes, bouncing face, arms typing at keyboard
- **Alert** (`waitingApproval`/`waitingQuestion`): wide startled eyes, jump, waving arms, `!` mark

Drawing uses an SVG-unit coordinate system scaled to the 27pt display frame. All geometry is defined as `CGRect` fills inside `Canvas` closures. `MascotView` wraps `ClawdView` with speed control via the `\.mascotSpeed` environment key.

## Color & Status

Agent status maps to visual indicators:
| Status | Meaning |
|--------|---------|
| `idle` | Session exists but agent is waiting for user input |
| `processing` | Agent is thinking / generating |
| `running` | Tool is actively executing |
| `waitingApproval` | Agent needs permission to proceed |
| `waitingQuestion` | Agent is asking the user a question |

## Layout Decisions

- **Notch-first**: Panel is designed around the MacBook notch dimensions. On external displays without a notch, it positions at top-center.
- **Auto-collapse**: Panel collapses when mouse leaves (configurable), hides in fullscreen apps (configurable).
- **Session rotation**: When multiple sessions are active, the compact view rotates through them on a timer.
- **Smart suppress**: Notification suppression is per-tab, not per-app — the app tracks which specific terminal tab is visible.

## Localization

`L10n.swift` contains all UI strings in both English and Simplified Chinese. Language is auto-detected from the system locale. Strings are accessed via static properties (e.g., `L10n.settingsGeneral`).

## Settings UI

7-tab `SettingsView` organized by concern — see [PRODUCT.md](PRODUCT.md#user-settings-7-tabs) for the full tab list. Settings are persisted via `UserDefaults` through `SettingsManager`, with all keys defined in `SettingsKey` enum and defaults in `SettingsDefaults`.
