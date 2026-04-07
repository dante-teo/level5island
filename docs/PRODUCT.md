# Product Overview

## What is CodeIsland?

CodeIsland is a macOS menu bar application that lives in the MacBook notch area and provides real-time status monitoring for AI coding agents. It eliminates the need to switch windows to check if an agent is waiting for approval, has finished a task, or needs input.

## Core Value Proposition

- **Ambient awareness** — Know what your AI agents are doing without context-switching
- **Direct interaction** — Approve permissions and answer agent questions from the panel
- **One-click navigation** — Jump directly to the terminal tab or IDE window running a session

## Supported Tools (9)

| Tool | Hook Format | Jump Target |
|------|------------|-------------|
| Claude Code | claude (13 events) | Terminal tab |
| Codex | flat (3 events) | Terminal |
| Gemini CLI | nested (6 events) | Terminal |
| Cursor | nested (10 events) | IDE |
| Copilot | copilot (6 events) | Terminal |
| Qoder | nested (10 events) | IDE |
| Factory | nested (10 events) | IDE |
| CodeBuddy | nested (10 events) | App/Terminal |
| OpenCode | JS plugin (all events) | App/Terminal |

## Key Features

### Notch-native UI
The panel expands from the MacBook notch in compact or expanded mode. Collapses when idle. Works on external displays (positions at top-center when no notch detected).

### Live Status Tracking
Each session shows: agent status (idle/processing/running/waiting), current tool call, tool history, subagent activity, recent chat messages, and session title.

### Smart Suppress
Tab-level terminal detection — notifications are only suppressed when the user is actively viewing the specific terminal tab for that session, not just the terminal app.

### Auto Hook Install
On launch, CodeIsland detects installed AI CLI tools and configures hooks automatically. Includes auto-repair and version tracking so hooks stay current across CLI upgrades.

### Sound Effects
Optional 8-bit sound notifications for session events (start, stop, approval needed, etc.).

### Bilingual UI
English and Simplified Chinese, auto-detected from system language.

## User Settings (7 tabs)

- **General** — Language, launch at login, display selection
- **Behavior** — Auto-hide, smart suppress, session cleanup timing
- **Appearance** — Panel height, font size, AI reply line count
- **Mascots** — Preview pixel-art characters and animations
- **Sound** — Per-event sound toggle
- **Hooks** — CLI installation status, reinstall/uninstall
- **About** — Version, links

## Distribution

- **Homebrew**: `brew tap dante-teo/tap && brew install --cask level5island`
- **Manual**: DMG download from GitHub Releases
- **Source**: `swift build && open .build/debug/CodeIsland.app`

## Requirements

- macOS 14.0 (Sonoma) or later
- Works best on MacBooks with a notch
