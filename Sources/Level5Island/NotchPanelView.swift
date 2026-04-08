import SwiftUI
import Level5IslandCore

private extension AnyTransition {
    static let cardReveal = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: -8)),
        removal: .opacity
    )
    static let listReveal = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: -12)),
        removal: .opacity
    )
}

@MainActor
struct NotchPanelView: View {
    var appState: AppState
    let hasNotch: Bool
    let notchHeight: CGFloat
    let notchW: CGFloat
    let screenWidth: CGFloat

    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    /// Delayed hover: prevents accidental expansion when mouse passes through
    @State private var hoverTimer: Timer?
    @State private var idleHovered = false
    @State private var curtainOffset: CGFloat = 0
    @State private var curtainOpacity: Double = 1
    @State private var displayedToolStatus: Bool = SettingsDefaults.showToolStatus
    @State private var contentVisible = false

    private var isActive: Bool { !appState.sessions.isEmpty }
    /// First launch / no-session state should still render a visible marker so the app
    /// doesn't disappear completely behind the physical notch.
    private var showIdleIndicator: Bool {
        !isActive && !hideWhenNoSession
    }
    private var showBar: Bool { isActive }
    private var shouldShowExpanded: Bool {
        showBar && appState.surface.isExpanded
    }

    private var mascotSize: CGFloat { min(27, notchHeight - 6) }
    private var compactWingWidth: CGFloat { mascotSize + 14 }

    /// Total panel width — adapts based on state and screen geometry
    private var panelWidth: CGFloat {
        let maxWidth = min(620, screenWidth - 40)
        if showIdleIndicator { return idleHovered ? notchW + compactWingWidth * 2 + 80 : notchW + compactWingWidth * 2 }
        if !isActive { return hasNotch ? notchW - 20 : notchW }
        if shouldShowExpanded { return min(max(notchW + 200, 580), maxWidth) }
        let wing = compactWingWidth
        let extra: CGFloat = appState.status == .idle ? 0 : 20
        // Reserve space for tool status — proportional to screen width
        let toolExtra: CGFloat = displayedToolStatus ? (hasNotch ? screenWidth * 0.03 : screenWidth * 0.04) : 0
        // Notch screens need wider wings so text beside the notch isn't clipped
        let notchBonus: CGFloat = hasNotch ? 60 : 0
        return notchW + wing * 2 + extra + toolExtra + notchBonus
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if showBar {
                    // Active: compact bar — wider version when expanded
                    HStack(spacing: 0) {
                        CompactLeftWing(appState: appState, expanded: shouldShowExpanded, mascotSize: mascotSize, hasNotch: hasNotch, showToolStatus: showToolStatus)
                        if hasNotch && !shouldShowExpanded {
                            Spacer(minLength: notchW)
                        } else if !shouldShowExpanded && showToolStatus {
                            CompactToolStatus(appState: appState)
                            Spacer(minLength: 0)
                        } else {
                            Spacer(minLength: 0)
                        }
                        CompactRightWing(appState: appState, expanded: shouldShowExpanded, hasNotch: hasNotch)
                    }
                    .frame(height: notchHeight)
                } else if showIdleIndicator {
                    IdleIndicatorBar(
                        mascotSize: mascotSize,
                        compactWingWidth: compactWingWidth,
                        notchW: notchW,
                        notchHeight: notchHeight,
                        hasNotch: hasNotch,
                        hovered: idleHovered
                    )
                } else {
                    // Idle: just the notch shell
                    Spacer()
                        .frame(height: notchHeight)
                }

                // Below-notch expanded content (staggered after panel shape)
                if shouldShowExpanded && contentVisible {
                    LinearGradient(
                        colors: [.clear, Design.border, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 0.5)
                    .padding(.horizontal, Design.spacingLG)

                    switch appState.surface {
                    case .approvalCard:
                        if let pending = appState.pendingPermission {
                            ApprovalBar(
                                tool: pending.event.toolName ?? "Unknown",
                                toolInput: pending.event.toolInput,
                                queuePosition: 1,
                                queueTotal: appState.permissionQueue.count,
                                onAllow: { appState.approvePermission(always: false) },
                                onAlwaysAllow: { appState.approvePermission(always: true) },
                                onDeny: { appState.denyPermission() }
                            )
                            .transition(.cardReveal)
                        }
                    case .questionCard(let sid):
                        let session = appState.sessions[sid]
                        if let q = appState.pendingQuestion {
                            QuestionFormView(
                                question: q.question,
                                sessionSource: session?.source,
                                sessionContext: session?.cwd,
                                queuePosition: 1,
                                queueTotal: appState.questionQueue.count,
                                onAnswer: { appState.answerQuestion($0) },
                                onSkip: { appState.skipQuestion() }
                            )
                            .transition(.cardReveal)
                        } else if let preview = appState.previewQuestionPayload {
                            QuestionFormView(
                                question: preview,
                                sessionSource: session?.source,
                                sessionContext: session?.cwd,
                                queuePosition: 1,
                                queueTotal: 1,
                                onAnswer: { _ in },
                                onSkip: { }
                            )
                            .transition(.cardReveal)
                        }
                    case .completionCard:
                        SessionListView(appState: appState, onlySessionId: appState.justCompletedSessionId)
                            .transition(.listReveal)
                    case .sessionList:
                        SessionListView(appState: appState, onlySessionId: nil)
                            .transition(.listReveal)
                    case .collapsed:
                        EmptyView()
                    }
                }
            }
            .frame(width: panelWidth)
            .clipped()
            .background(
                NotchPanelShape(
                    topExtension: shouldShowExpanded ? 14 : 3,
                    bottomRadius: shouldShowExpanded ? 24 : 12,
                    minHeight: notchHeight
                )
                .fill(.black)
            )
            .offset(y: curtainOffset)
            .opacity(curtainOpacity)
            .onChange(of: showToolStatus) { _, newValue in
                // Phase 1: entire bar slides up and fades out
                withAnimation(.easeIn(duration: 0.2)) {
                    curtainOffset = -notchHeight
                    curtainOpacity = 0
                }
                // Phase 2: switch width while hidden
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    displayedToolStatus = newValue
                }
                // Phase 3: entire bar slides back down
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        curtainOffset = 0
                        curtainOpacity = 1
                    }
                }
            }
            .onAppear { displayedToolStatus = showToolStatus }
            .contentShape(Rectangle())
            .onHover { hovering in
                // Idle indicator hover
                if showIdleIndicator {
                    withAnimation(NotchAnimation.micro) { idleHovered = hovering }
                    return
                }
                switch appState.surface {
                case .approvalCard, .questionCard: return
                case .completionCard:
                    // Completion card: mark entered on hover-in, block collapse until entered
                    if hovering {
                        appState.completionHasBeenEntered = true
                    } else if appState.completionHasBeenEntered {
                        // Mouse entered then left — allow collapse
                        hoverTimer?.invalidate()
                        hoverTimer = nil
                        withAnimation(NotchAnimation.close) {
                            appState.surface = .collapsed
                            appState.cancelCompletionQueue()
                        }
                    }
                    return
                default: break
                }
                // Respect collapseOnMouseLeave setting
                if !hovering && !SettingsManager.shared.collapseOnMouseLeave { return }
                // Smart suppress: don't auto-expand when active session's terminal is foreground
                if hovering && smartSuppress {
                    if let delegate = NSApp.delegate as? AppDelegate,
                       let pc = delegate.panelController,
                       pc.isActiveTerminalForeground() {
                        return
                    }
                }

                if hovering {
                    // Delay expansion to avoid accidental triggers
                    hoverTimer?.invalidate()
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                        Task { @MainActor in
                            withAnimation(NotchAnimation.open) {
                                appState.surface = .sessionList
                                appState.cancelCompletionQueue()
                                if appState.activeSessionId == nil {
                                    appState.activeSessionId = appState.sessions.keys.sorted().first
                                }
                            }
                        }
                    }
                } else {
                    // Collapse with brief delay to prevent flicker on accidental mouse-out
                    hoverTimer?.invalidate()
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                        Task { @MainActor in
                            withAnimation(NotchAnimation.close) {
                                appState.surface = .collapsed
                            }
                        }
                    }
                }
            }

            Spacer()
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: shouldShowExpanded) { _, expanded in
            if expanded {
                withAnimation(NotchAnimation.contentReveal) {
                    contentVisible = true
                }
            } else {
                contentVisible = false
            }
        }
    }
}


// MARK: - Compact Wings (notch-level, 32px height)

/// Left side: pixel character + status info
@MainActor private struct CompactLeftWing: View {
    var appState: AppState
    let expanded: Bool
    let mascotSize: CGFloat
    let hasNotch: Bool
    let showToolStatus: Bool
    @AppStorage(SettingsKey.sessionGroupingMode) private var groupingMode = SettingsDefaults.sessionGroupingMode

    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var displaySession: SessionSnapshot? {
        guard let sid = displaySessionId else { return nil }
        return appState.sessions[sid]
    }
    private var displaySource: String { displaySession?.source ?? appState.primarySource }
    private var displayStatus: AgentStatus { displaySession?.status ?? .idle }
    private var liveTool: String? { displaySession?.currentTool }
    @State private var shownTool: String?
    @State private var lingerTimer: Timer?
    @State private var hoverPreviewTimer: Timer?
    @State private var showHoverCard = false

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                AppLogoView(size: 36, showBackground: false)
                if appState.sessions.count > 1 {
                    HStack(spacing: 2) {
                        ForEach([("all", "All"), ("status", "Status"), ("cli", "CLI")], id: \.0) { tag, label in
                            let selected = groupingMode == tag
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { groupingMode = tag }
                            } label: {
                                Text(label)
                                    .font(Design.caption(10, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Design.statusActive : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(selected ? .white.opacity(0.1) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.05)))
                }
            } else {
                MascotView(source: displaySource, status: displayStatus, size: mascotSize)
                    .id(displaySource)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: displaySource)
                    .onHover { hovering in
                        hoverPreviewTimer?.invalidate()
                        if hovering {
                            hoverPreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                Task { @MainActor in
                                    showHoverCard = true
                                }
                            }
                        } else {
                            showHoverCard = false
                        }
                    }
                    .popover(isPresented: $showHoverCard, arrowEdge: .bottom) {
                        if let session = displaySession, let sid = displaySessionId {
                            SessionHoverCard(session: session, sessionId: sid)
                        }
                    }

                // On notch screens, show tool name only (no description, space is tight)
                if hasNotch, showToolStatus, let tool = shownTool {
                    Text(tool)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Design.toolColor(tool))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
        }
        .padding(.leading, 6)
        .clipped()
        .onChange(of: liveTool) { _, newTool in
            lingerTimer?.invalidate()
            if let newTool {
                withAnimation(.easeInOut(duration: 0.2)) { shownTool = newTool }
            } else {
                lingerTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.3)) { shownTool = nil }
                    }
                }
            }
        }
        // Session rotation: immediately sync tool to avoid stale linger from previous session
        .onChange(of: appState.rotatingSessionId) { _, _ in
            lingerTimer?.invalidate()
            let newTool = liveTool
            withAnimation(.easeInOut(duration: 0.2)) { shownTool = newTool }
        }
    }
}

/// Right side: project name + session count (detailed) or just count (simple)
private struct CompactRightWing: View {
    var appState: AppState
    let expanded: Bool
    let hasNotch: Bool
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var projectName: String? {
        guard let sid = displaySessionId, let cwd = appState.sessions[sid]?.cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                    soundEnabled.toggle()
                }
                NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                    SettingsWindowController.shared.show()
                }
                NotchIconButton(icon: "power", tint: Design.statusError, tooltip: l10n["quit"]) {
                    NSApplication.shared.terminate(nil)
                }
            } else {
                // Pending approval/question badge
                if appState.status.needsAttention {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Design.statusWarning)
                        .symbolEffect(.pulse, options: .repeating)
                }

                if showToolStatus {
                    // Detailed mode: session count (project name is shown in center on non-notch)
                    HStack(spacing: 1) {
                        let active = appState.activeSessionCount
                        let total = appState.totalSessionCount
                        if active > 0 {
                            Text("\(active)")
                                .foregroundStyle(Design.statusActive)
                            Text("/")
                                .foregroundStyle(.tertiary)
                        }
                        Text("\(total)")
                            .foregroundStyle(.primary)
                    }
                    .font(Design.headline(12)).monospacedDigit()
                } else {
                    // Simple mode: original session count only
                    HStack(spacing: 1) {
                        let active = appState.activeSessionCount
                        let total = appState.totalSessionCount
                        if active > 0 {
                            Text("\(active)")
                                .foregroundStyle(Design.statusActive)
                            Text("/")
                                .foregroundStyle(.tertiary)
                        }
                        Text("\(total)")
                            .foregroundStyle(.primary)
                    }
                    .font(Design.headline(13, weight: .bold)).monospacedDigit()
                }
            }
        }
        .padding(.trailing, 6)
    }
}

// MARK: - Compact Tool Status (non-notch center area)

/// Shows the current tool activity in the center of the bar on non-notch screens.
/// Keeps the last tool visible for a short linger period to avoid flashing.
@MainActor private struct CompactToolStatus: View {
    var appState: AppState

    /// Single source of truth: all fields derive from the same session.
    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var displaySession: SessionSnapshot? {
        guard let sid = displaySessionId else { return nil }
        return appState.sessions[sid]
    }
    private var liveTool: String? { displaySession?.currentTool }
    private var liveDesc: String? { displaySession?.toolDescription }
    private var displayStatus: AgentStatus { displaySession?.status ?? .idle }
    private var projectName: String? {
        guard let cwd = displaySession?.cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    @State private var shownTool: String?
    @State private var shownDesc: String?
    @State private var lingerTimer: Timer?

    /// Extract meaningful part of description — file paths show last component
    private func shortDesc(_ desc: String) -> String {
        let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }

    /// Whether there's any activity worth showing (tool running or thinking)
    private var hasActivity: Bool { shownTool != nil || displayStatus == .processing }

    var body: some View {
        HStack(spacing: 5) {
            // Project name — only shown when there's tool activity
            if hasActivity, let project = projectName {
                Text(project)
                    .foregroundStyle(.secondary)
                    .id("center-project-\(displaySessionId ?? "")")
                    .transition(.opacity)
            }

            // Tool status or thinking indicator
            if let tool = shownTool {
                TypingIndicator(fontSize: 11, label: tool, bright: true, color: Design.toolColor(tool))
                    .id("tool-\(tool)-\(appState.rotatingSessionId ?? "")")
                if let desc = shownDesc {
                    Text(shortDesc(desc))
                        .foregroundStyle(.secondary)
                        .truncationMode(.tail)
                }
            } else if displayStatus == .processing {
                TypingIndicator(fontSize: 11, label: "thinking", bright: true)
                    .id("thinking-\(appState.rotatingSessionId ?? "")")
            }
        }
        .font(Design.caption(11))
        .lineLimit(1)
        .padding(.leading, 6)
        .animation(.easeInOut(duration: 0.25), value: shownTool)
        .animation(.easeInOut(duration: 0.15), value: shownDesc)
        .animation(.easeInOut(duration: 0.3), value: appState.rotatingSessionId)
        .onChange(of: liveTool) { _, newTool in
            lingerTimer?.invalidate()
            if let newTool {
                shownTool = newTool
                shownDesc = liveDesc
            } else {
                lingerTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.3)) {
                            shownTool = nil
                            shownDesc = nil
                        }
                    }
                }
            }
        }
        .onChange(of: liveDesc) { _, newDesc in
            if liveTool != nil { shownDesc = newDesc }
        }
        // Session rotation: immediately sync to avoid stale linger from previous session
        .onChange(of: appState.rotatingSessionId) { _, _ in
            lingerTimer?.invalidate()
            withAnimation(.easeInOut(duration: 0.2)) {
                shownTool = liveTool
                shownDesc = liveDesc
            }
        }
    }
}

private struct NotchIconButton: View {
    let icon: String
    var tint: Color = .white
    var tooltip: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(hovering ? 1.0 : 0.7))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tint.opacity(hovering ? 0.15 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
        .help(tooltip ?? "")
    }
}

// MARK: - Idle Indicator Bar

private struct IdleIndicatorBar: View {
    let mascotSize: CGFloat
    let compactWingWidth: CGFloat
    let notchW: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool
    let hovered: Bool
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled

    var body: some View {
        HStack(spacing: 0) {
            // Left: mascot
            HStack(spacing: 6) {
                MascotView(source: "claude", status: .idle, size: mascotSize)
                    .opacity(hovered ? 0.9 : 0.5)
            }
            .padding(.leading, 6)

            Spacer(minLength: hasNotch ? notchW : 0)

            // Right: expanded shows text + buttons, collapsed shows nothing
            if hovered {
                HStack(spacing: 8) {
                    Text("0")
                        .font(Design.headline(13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 4) {
                        NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                            soundEnabled.toggle()
                        }
                        NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                            SettingsWindowController.shared.show()
                        }
                        NotchIconButton(icon: "power", tint: Design.statusError, tooltip: l10n["quit"]) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .frame(height: notchHeight)
        .animation(NotchAnimation.micro, value: hovered)
    }
}

// MARK: - Approval Bar (below notch, auto-expanded)

private struct ApprovalBar: View {
    let tool: String
    let toolInput: [String: Any]?
    let queuePosition: Int
    let queueTotal: Int
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let onDeny: () -> Void

    private var fileName: String? {
        guard let fp = toolInput?["file_path"] as? String else { return nil }
        return (fp as NSString).lastPathComponent
    }

    private var filePath: String? {
        toolInput?["file_path"] as? String
    }

    private var serverName: String? {
        toolInput?["server_name"] as? String
    }

    @ViewBuilder
    private var queueBadge: some View {
        if queueTotal > 1 {
            Text("\(queuePosition)/\(queueTotal)")
                .font(Design.caption(9, weight: .bold)).monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    var body: some View {
        VStack(spacing: Design.spacingSM) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.statusWarning)
                    Text(tool)
                        .font(Design.mono(11, weight: .bold))
                        .foregroundStyle(Design.statusWarning)
                    if let server = serverName {
                        Text("(\(server))")
                            .font(Design.mono(9))
                            .foregroundStyle(.blue)
                    }
                    if let name = fileName {
                        Text(name)
                            .font(Design.caption(10))
                            .foregroundStyle(.secondary)
                    }
                    queueBadge
                    Spacer()
                }
                .padding(.horizontal, 14)

                if toolInput != nil {
                    toolDetailView
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary)
                }

                HStack(spacing: 6) {
                    PixelButton(label: L10n.shared["deny"], fg: .white, bg: Design.statusError.opacity(0.6), border: Design.statusError.opacity(0.4), action: onDeny)
                    PixelButton(label: L10n.shared["allow_once"], fg: .white, bg: Design.statusActive.opacity(0.5), border: Design.statusActive.opacity(0.4), action: onAllow)
                    PixelButton(label: L10n.shared["always"], fg: .white, bg: Design.statusQuestion.opacity(0.5), border: Design.statusQuestion.opacity(0.4), action: onAlwaysAllow)
                }
                .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Design.statusWarning.opacity(0.35)
                .frame(height: 1)
                .blur(radius: 2)
        }
    }

    @ViewBuilder
    private var toolDetailView: some View {
        switch tool {
        case "Bash":
            // Show command as a terminal prompt
            VStack(alignment: .leading, spacing: 2) {
                if let cmd = toolInput?["command"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("$")
                            .font(Design.mono(10, weight: .bold))
                            .foregroundStyle(Design.statusActive)
                        Text(cmd)
                            .font(Design.mono(10))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(3)
                    }
                }
            }

        case "Edit":
            // Show diff style: - old / + new
            VStack(alignment: .leading, spacing: 3) {
                if let fp = filePath {
                    Text(fp)
                        .font(Design.mono(9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let old = toolInput?["old_string"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("−")
                            .font(Design.mono(10, weight: .bold))
                            .foregroundStyle(Design.statusError)
                        Text(old.prefix(120))
                            .font(Design.mono(9.5))
                            .foregroundStyle(Design.statusError.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                if let new = toolInput?["new_string"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("+")
                            .font(Design.mono(10, weight: .bold))
                            .foregroundStyle(Design.statusActive)
                        Text(new.prefix(120))
                            .font(Design.mono(9.5))
                            .foregroundStyle(Design.statusActive.opacity(0.7))
                            .lineLimit(2)
                    }
                }
            }

        case "Write":
            // Show file path + content preview
            VStack(alignment: .leading, spacing: 3) {
                if let fp = filePath {
                    Text(fp)
                        .font(Design.mono(9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let content = toolInput?["content"] as? String {
                    Text(content.prefix(200))
                        .font(Design.mono(9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

        case "Read":
            // Show file path + line range
            VStack(alignment: .leading, spacing: 2) {
                if let fp = filePath {
                    Text(fp)
                        .font(Design.mono(9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let offset = toolInput?["offset"] as? Int,
                   let limit = toolInput?["limit"] as? Int {
                    Text("\(L10n.shared["lines"]) \(offset + 1)–\(offset + limit)")
                        .font(Design.mono(9))
                        .foregroundStyle(.tertiary)
                }
            }

        case "Grep":
            // Show pattern + optional path
            VStack(alignment: .leading, spacing: 2) {
                if let pattern = toolInput?["pattern"] as? String {
                    HStack(alignment: .top, spacing: 4) {
                        Text("/")
                            .font(Design.mono(10, weight: .bold))
                            .foregroundStyle(.purple)
                        Text(pattern)
                            .font(Design.mono(10))
                            .foregroundStyle(.purple.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                if let path = toolInput?["path"] as? String {
                    Text(path)
                        .font(Design.mono(9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

        case "Glob":
            // Show glob pattern
            VStack(alignment: .leading, spacing: 2) {
                if let pattern = toolInput?["pattern"] as? String {
                    Text(pattern)
                        .font(Design.mono(10))
                        .foregroundStyle(.blue)
                        .lineLimit(2)
                }
                if let path = toolInput?["path"] as? String {
                    Text(path)
                        .font(Design.mono(9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

        default:
            // Generic: show all key-value pairs
            VStack(alignment: .leading, spacing: 2) {
                if let input = toolInput {
                    ForEach(Array(input.keys.sorted().prefix(4)), id: \.self) { key in
                        let val = input[key].map { "\($0)" } ?? ""
                        HStack(alignment: .top, spacing: 4) {
                            Text(key)
                                .font(Design.mono(9, weight: .semibold))
                                .foregroundStyle(.blue)
                            Text(String(val.prefix(100)))
                                .font(Design.mono(9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Option Row

struct OptionRow: View {
    let index: Int
    let label: String
    let description: String?
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.spacingSM) {
                // Number
                Text("\(index)")
                    .font(Design.caption(10, weight: .semibold))
                    .foregroundStyle(accent.opacity(hovering ? 1 : 0.6))
                    .frame(width: 16, height: 16)
                    .background(accent.opacity(hovering ? 0.15 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                // Label + Description
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Design.body(10.5, weight: hovering ? .semibold : .regular))
                        .foregroundStyle(hovering ? .primary : .secondary)
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(Design.caption(9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if hovering {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? .white.opacity(0.08) : .white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(hovering ? accent.opacity(0.3) : .clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }
}

struct PixelButton: View {
    let label: String
    let fg: Color
    let bg: Color
    let border: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Design.caption(10, weight: .semibold))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    hovering ? bg : bg.opacity(0.9),
                                    hovering ? bg.opacity(0.8) : bg.opacity(0.7)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(hovering ? border : border.opacity(0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }
}

// MARK: - Session List

@MainActor private struct SessionListView: View {
    var appState: AppState
    /// When set, only show this session (auto-expand on completion)
    var onlySessionId: String? = nil
    @AppStorage(SettingsKey.sessionGroupingMode) private var groupingMode = SettingsDefaults.sessionGroupingMode
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions

    private var groupedSessions: [(header: String, source: String?, ids: [String])] {
        if let only = onlySessionId, appState.sessions[only] != nil {
            return [("", nil, [only])]
        }

        let sorted = appState.sessions.keys.sorted()

        switch groupingMode {
        case "status":
            let l10n = L10n.shared
            let groups: [(Set<AgentStatus>, String)] = [
                ([.running], l10n["status_running"]),
                ([.waitingApproval, .waitingQuestion], l10n["status_waiting"]),
                ([.processing, .compacting], l10n["status_processing"]),
                ([.idle], l10n["status_idle"]),
            ]
            var result: [(String, String?, [String])] = []
            for (statuses, label) in groups {
                let ids = sorted.filter { id in
                    guard let s = appState.sessions[id] else { return false }
                    return statuses.contains(s.status)
                }
                if !ids.isEmpty {
                    result.append(("\(label) (\(ids.count))", nil, ids))
                }
            }
            return result

        case "cli":
            let cliOrder: [(source: String, name: String)] = [
                ("claude", "Claude"),
            ]
            var result: [(String, String?, [String])] = []
            var seen = Set<String>()
            for cli in cliOrder {
                let ids = sorted.filter { id in
                    appState.sessions[id]?.source == cli.source
                }
                ids.forEach { seen.insert($0) }
                if !ids.isEmpty {
                    result.append(("\(cli.name) (\(ids.count))", cli.source, ids))
                }
            }
            let remaining = sorted.filter { !seen.contains($0) }
            if !remaining.isEmpty {
                result.append(("\(L10n.shared["other"]) (\(remaining.count))", nil, remaining))
            }
            return result

        default: // "all"
            return [("", nil, sorted)]
        }
    }

    var body: some View {
        // Compute once per render — groupedSessions, totalCount, needsScroll
        let groups = groupedSessions
        let totalSessionCount = groups.reduce(0) { $0 + $1.ids.count }
        let needsScroll = onlySessionId == nil && totalSessionCount > maxVisibleSessions
        let content = VStack(spacing: 6) {
            ForEach(groups, id: \.header) { group in
                if !group.header.isEmpty {
                    HStack(spacing: 6) {
                        if group.source != nil {
                            ClaudeLogo(size: 14)
                        }
                        Text(group.header)
                            .font(Design.caption(11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                }

                ForEach(group.ids, id: \.self) { sessionId in
                    if let session = appState.sessions[sessionId] {
                        SessionCard(
                            sessionId: sessionId,
                            session: session,
                            isCompletion: onlySessionId != nil
                        )
                    }
                }
            }

            // "Show all sessions" — hover with delay to expand
            if onlySessionId != nil && appState.sessions.count > 1 {
                SessionsExpandLink(count: appState.sessions.count) {
                    withAnimation(NotchAnimation.open) {
                        appState.surface = .sessionList
                        appState.cancelCompletionQueue()
                    }
                }
            }
        }
        .padding(.vertical, 4)

        if needsScroll {
            ThinScrollView(maxHeight: CGFloat(maxVisibleSessions) * 90) {
                content
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0,
                    style: .continuous
                )
            )
        } else {
            content
        }
    }
}

/// Thin overlay scrollbar via NSScrollView — ignores system "show scrollbar" preference.
private struct ThinScrollView<Content: View>: NSViewRepresentable {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.drawsBackground = false
        scrollView.scrollerKnobStyle = .light

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: maxHeight),
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hosting = scrollView.documentView as? NSHostingView<Content> {
            hosting.rootView = content
        }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
    }
}

private struct SessionIdentityLine: View {
    let session: SessionSnapshot
    let sessionId: String
    let projectFontSize: CGFloat
    let projectColor: Color
    let sessionFontSize: CGFloat
    let sessionColor: Color
    let dividerColor: Color
    let cardHovering: Bool

    private var displaySessionId: String { session.displaySessionId(sessionId: sessionId) }

    var body: some View {
        HStack(spacing: 4) {
            ProjectNameLink(
                name: session.displayName,
                cwd: session.cwd,
                fontSize: projectFontSize,
                color: projectColor,
                cardHovering: cardHovering
            )
            .layoutPriority(2)

            if let sessionLabel = session.sessionLabel {
                Text("#\(sessionLabel)")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Text("·")
                    .font(.system(size: sessionFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(dividerColor)

                Text("#\(shortSessionId(displaySessionId))")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor.opacity(0.6))
                    .fixedSize()
            } else {
                Text("#\(shortSessionId(displaySessionId))")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor.opacity(0.6))
                    .fixedSize()
            }
        }
    }
}

private struct ProjectNameLink: View {
    let name: String
    let cwd: String?
    let fontSize: CGFloat
    let color: Color
    let cardHovering: Bool

    var body: some View {
        Text(name)
            .font(Design.headline(fontSize, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .overlay(alignment: .bottom) {
                if cwd != nil {
                    GeometryReader { geo in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: geo.size.height))
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundStyle(color.opacity(cardHovering ? 0.5 : 0.2))
                    }
                }
            }
            .onTapGesture {
                if let cwd = cwd {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
            .help(cwd != nil ? "\(L10n.shared["open_path"]) \(cwd!)" : "")
    }
}

private struct SessionsExpandLink: View {
    let count: Int
    let action: () -> Void
    @State private var hovering = false
    @State private var hoverTimer: Timer?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle().fill(Design.borderHover).frame(height: 1)
                Text("\(count) \(L10n.shared["n_sessions"])")
                    .font(Design.caption(11))
                    .foregroundStyle(hovering ? .secondary : .tertiary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(hovering ? .tertiary : .quaternary)
                Rectangle().fill(Design.borderHover).frame(height: 1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(NotchAnimation.micro) { hovering = h }
            hoverTimer?.invalidate()
            hoverTimer = nil
            if h {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    Task { @MainActor in action() }
                }
            }
        }
    }
}

private struct SessionCard: View {
    let sessionId: String
    let session: SessionSnapshot
    var isCompletion: Bool = false
    @State private var hovering = false
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    private var fontSize: CGFloat { CGFloat(contentFontSize) }
    private var aiLineLimit: Int? { aiMessageLines > 0 ? aiMessageLines : nil }
    private var statusNameColor: Color {
        if session.status == .idle && session.interrupted {
            return Design.statusError
        }
        switch session.status {
        case .processing, .running, .compacting:  return Design.statusActive
        case .waitingApproval, .waitingQuestion:   return Design.statusWarning
        case .idle:                                return .primary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Column 1: Character + subagent icons
            VStack(spacing: 3) {
                MascotView(source: session.source, status: session.status, size: 32)
                    .shadow(
                        color: session.status != .idle ? statusNameColor.opacity(0.3) : .clear,
                        radius: session.status != .idle ? 6 : 0
                    )
                if showAgentDetails && !session.subagents.isEmpty {
                    let sorted = session.subagents.values.sorted { $0.startTime < $1.startTime }
                    // Grid: 4 per row, 8px icons
                    let rows = stride(from: 0, to: sorted.count, by: 4).map {
                        Array(sorted[$0..<min($0 + 4, sorted.count)])
                    }
                    VStack(spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 1) {
                                ForEach(row, id: \.agentId) { sub in
                                    MiniAgentIcon(active: sub.status != .idle, size: 8)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 36)

            // Column 2: Content
            VStack(alignment: .leading, spacing: 6) {
                // Header: project name + optional session label + short ID
                HStack(alignment: .center, spacing: 8) {
                    SessionIdentityLine(
                        session: session,
                        sessionId: sessionId,
                        projectFontSize: fontSize + 2,
                        projectColor: statusNameColor,
                        sessionFontSize: fontSize,
                        sessionColor: .white.opacity(0.76),
                        dividerColor: .white.opacity(0.28),
                        cardHovering: hovering
                    )
                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        if session.interrupted {
                            SessionTag("INT", color: Design.statusWarning)
                        }
                        SessionTag(Design.timeAgo(session.startTime))
                        TerminalJumpButton(session: session, sessionId: sessionId)
                    }
                }

                // Session title: first user prompt (hide when detailed mode shows chat history)
                if let summary = session.smartSummary ?? session.lastUserPrompt,
                   session.recentMessages.isEmpty {
                    Text(summary)
                        .font(Design.body(fontSize))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

            // Chat history + live status
            if !session.recentMessages.isEmpty || session.status != .idle {
                VStack(alignment: .leading, spacing: 3) {
                    // Chat messages (detailed mode only)
                    let visibleMessages = session.status != .idle
                        ? Array(session.recentMessages.suffix(2))
                        : session.recentMessages
                    ForEach(visibleMessages) { msg in
                        if msg.isUser {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: fontSize - 1))
                                    .foregroundStyle(Design.statusActive)
                                    .frame(width: fontSize + 2)
                                Text(renderUserText(msg.text))
                                    .font(Design.body(fontSize, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 4) {
                                ClaudeLogo(size: fontSize + 1)
                                    .frame(width: fontSize + 2)
                                Text(renderMarkdown(compactText(stripDirectives(msg.text))))
                                    .font(Design.body(fontSize))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .lineLimit(aiLineLimit)
                                    .truncationMode(.tail)
                            }
                        }
                    }

                    // Working indicator: show what AI is doing right now
                    if session.status != .idle {
                        HStack(spacing: 4) {
                            ClaudeLogo(size: fontSize + 1)
                                .frame(width: fontSize + 2)
                            if let tool = session.currentTool {
                                let desc: String = {
                                    if tool == "Agent", session.activeSubagentCount > 0 {
                                        let agentDesc = session.toolDescription ?? "Agent"
                                        let count = String(format: L10n.shared["n_active"], session.activeSubagentCount)
                                        return "\(agentDesc) (\(count))"
                                    }
                                    return session.toolDescription ?? tool
                                }()
                                Text(desc)
                                    .font(Design.body(fontSize))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                TypingIndicator(fontSize: fontSize, label: "thinking")
                            }
                        }
                    }
                }
                .padding(.leading, 4)
            }
            } // end Column 2 VStack
        } // end HStack
        .padding(.horizontal, Design.spacingLG)
        .padding(.vertical, Design.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Design.cardRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(hovering ? 0.10 : 0.05),
                            .white.opacity(hovering ? 0.06 : 0.02)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardRadius)
                .strokeBorder(
                    hovering ? statusNameColor.opacity(0.25) : Design.border,
                    lineWidth: 0.5
                )
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
        .onTapGesture {
            if isCompletion {
                TerminalActivator.activate(session: session, sessionId: sessionId)
            }
        }
    }

    /// Collapse consecutive blank lines and trim leading/trailing whitespace
    private func compactText(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { result, line in
                // Skip consecutive empty lines
                if line.isEmpty && (result.last?.isEmpty ?? true) { return }
                result.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        ChatMessageTextFormatter.inlineMarkdown(text)
    }

    private func renderUserText(_ text: String) -> AttributedString {
        ChatMessageTextFormatter.literalText(text)
    }

}

// MARK: - Claude Logo (official sunburst from simple-icons, viewBox 0 0 24 24)

struct ClaudeLogo: View {
    var size: CGFloat = 22
    private static let color = Design.terracotta

    // Official Claude logo SVG path (source: simple-icons)
    fileprivate static let svgPath = "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"

    var body: some View {
        ClaudeLogoShape()
            .fill(Self.color)
            .frame(width: size, height: size)
    }
}

private struct ClaudeLogoShape: Shape {
    private static let basePath: Path = ClaudeLogoShape.parseSVGPath(ClaudeLogo.svgPath)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Self.basePath.applying(transform)
    }

    // Minimal SVG path parser for m/l/h/v/c/z commands
    private static func parseSVGPath(_ d: String) -> Path {
        var path = Path()
        var x: CGFloat = 0, y: CGFloat = 0
        var i = d.startIndex
        var cmd: Character = "m"

        func skipWS() {
            while i < d.endIndex && (d[i] == " " || d[i] == ",") { i = d.index(after: i) }
        }

        func peekNum() -> Bool {
            guard i < d.endIndex else { return false }
            let c = d[i]
            return c == "-" || c == "." || c.isNumber
        }

        func num() -> CGFloat {
            skipWS()
            var s = ""
            if i < d.endIndex && d[i] == "-" { s.append(d[i]); i = d.index(after: i) }
            var hasDot = false
            while i < d.endIndex {
                let c = d[i]
                if c == "." {
                    if hasDot { break }
                    hasDot = true; s.append(c); i = d.index(after: i)
                } else if c.isNumber {
                    s.append(c); i = d.index(after: i)
                } else { break }
            }
            return CGFloat(Double(s) ?? 0)
        }

        while i < d.endIndex {
            skipWS()
            guard i < d.endIndex else { break }
            let c = d[i]
            if c.isLetter {
                cmd = c; i = d.index(after: i)
            }

            switch cmd {
            case "m":
                let dx = num(), dy = num(); x += dx; y += dy
                path.move(to: CGPoint(x: x, y: y))
                cmd = "l" // subsequent coords are implicit lineTo
            case "M":
                x = num(); y = num()
                path.move(to: CGPoint(x: x, y: y))
                cmd = "L"
            case "l":
                let dx = num(), dy = num(); x += dx; y += dy
                path.addLine(to: CGPoint(x: x, y: y))
            case "L":
                x = num(); y = num()
                path.addLine(to: CGPoint(x: x, y: y))
            case "h":
                x += num(); path.addLine(to: CGPoint(x: x, y: y))
            case "H":
                x = num(); path.addLine(to: CGPoint(x: x, y: y))
            case "v":
                y += num(); path.addLine(to: CGPoint(x: x, y: y))
            case "V":
                y = num(); path.addLine(to: CGPoint(x: x, y: y))
            case "c":
                let dx1 = num(), dy1 = num(), dx2 = num(), dy2 = num(), dx = num(), dy = num()
                path.addCurve(to: CGPoint(x: x+dx, y: y+dy),
                              control1: CGPoint(x: x+dx1, y: y+dy1),
                              control2: CGPoint(x: x+dx2, y: y+dy2))
                x += dx; y += dy
            case "C":
                let x1 = num(), y1 = num(), x2 = num(), y2 = num()
                x = num(); y = num()
                path.addCurve(to: CGPoint(x: x, y: y),
                              control1: CGPoint(x: x1, y: y1),
                              control2: CGPoint(x: x2, y: y2))
            case "Z", "z":
                path.closeSubpath()
            default:
                i = d.index(after: i)
            }

            // Handle repeated implicit commands
            skipWS()
            if i < d.endIndex && peekNum() && "mlhvcMLHVC".contains(cmd) {
                continue
            }
        }
        return path
    }
}

// MARK: - Notch Panel Shape (inverse radius at top, regular radius at bottom)

private struct NotchPanelShape: Shape {
    var topExtension: CGFloat
    var bottomRadius: CGFloat
    /// Fixed minimum height — NOT animated, prevents spring overshoot from exposing the notch
    var minHeight: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topExtension, bottomRadius) }
        set {
            topExtension = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ext = topExtension
        let maxY = max(rect.maxY, rect.minY + minHeight)
        let br = min(bottomRadius, rect.width / 4, (maxY - rect.minY) / 2)
        // Smoothness factor for continuous-curvature corners (superellipse approximation).
        // 0.5523 = perfect circle; higher values tighten the curve for an Apple squircle feel.
        let k: CGFloat = 0.62

        var p = Path()
        // Top edge (extends into notch area via wings)
        p.move(to: CGPoint(x: rect.minX - ext, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + ext, y: rect.minY))
        // Right shoulder: cubic bezier tangent to top line (horizontal) and right side (vertical)
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + ext),
            control1: CGPoint(x: rect.maxX + ext * 0.35, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + ext * 0.35)
        )
        // Right side down to bottom-right corner
        p.addLine(to: CGPoint(x: rect.maxX, y: maxY - br))
        // Bottom-right: cubic bezier for continuous-curvature corner
        p.addCurve(
            to: CGPoint(x: rect.maxX - br, y: maxY),
            control1: CGPoint(x: rect.maxX, y: maxY - br * (1 - k)),
            control2: CGPoint(x: rect.maxX - br * (1 - k), y: maxY)
        )
        // Bottom edge
        p.addLine(to: CGPoint(x: rect.minX + br, y: maxY))
        // Bottom-left: cubic bezier for continuous-curvature corner
        p.addCurve(
            to: CGPoint(x: rect.minX, y: maxY - br),
            control1: CGPoint(x: rect.minX + br * (1 - k), y: maxY),
            control2: CGPoint(x: rect.minX, y: maxY - br * (1 - k))
        )
        // Left side up to shoulder
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ext))
        // Left shoulder: cubic bezier tangent to left side (vertical) and top line (horizontal)
        p.addCurve(
            to: CGPoint(x: rect.minX - ext, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + ext * 0.35),
            control2: CGPoint(x: rect.minX - ext * 0.35, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

/// Collapsed single-line row for idle sessions >15 min
private struct TerminalJumpButton: View {
    let session: SessionSnapshot
    let sessionId: String
    @State private var hovering = false

    private let green = Design.statusActive

    private static var termIconCache: [String: NSImage] = [:]

    private var termIcon: NSImage? {
        let bid = session.termBundleId
        guard let bid else { return nil }
        if let cached = Self.termIconCache[bid] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.termIconCache[bid] = icon
        return icon
    }

    var body: some View {
        Button {
            TerminalActivator.activate(session: session, sessionId: sessionId)
        } label: {
            HStack(spacing: 4) {
                if let icon = termIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 13, height: 13)
                }
                if let term = session.terminalName {
                    Text(term)
                        .font(Design.caption(9.5))
                        .foregroundStyle(green)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(green.opacity(hovering ? 1.0 : 0.5))
                    .offset(x: hovering ? 2 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(green.opacity(hovering ? 0.18 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hovering = h }
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private struct SessionTag: View {
    let text: String
    var color: Color = .white.opacity(0.7)

    init(_ text: String, color: Color = .white.opacity(0.7)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Design.caption(9.5)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Typing Indicator (three bouncing dots)

private struct TypingIndicator: View {
    let fontSize: CGFloat
    var label: String? = nil
    var bright: Bool = false
    var color: Color? = nil
    @State private var phase: CGFloat = -60

    var body: some View {
        if let label {
            let baseColor: Color = color ?? .white
            let baseOpacity: Double = bright ? 0.6 : 0.35
            let peakOpacity: Double = bright ? 0.8 : 0.5
            let midOpacity: Double = bright ? 0.5 : 0.3
            let bandWidth: CGFloat = bright ? 80 : 60
            let duration: Double = 2.5
            let endPhase: CGFloat = bright ? 100 : 80
            let startPhase: CGFloat = bright ? -80 : -60

            Text(label)
                .font(Design.caption(fontSize))
                .foregroundStyle(baseColor.opacity(baseOpacity))
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(midOpacity), location: bright ? 0.35 : 0.4),
                            .init(color: .white.opacity(peakOpacity), location: 0.5),
                            .init(color: .white.opacity(midOpacity), location: bright ? 0.65 : 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: phase)
                    .mask(
                        Text(label)
                            .font(Design.caption(fontSize))
                    )
                )
                .onAppear {
                    phase = startPhase
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: false)) {
                        phase = endPhase
                    }
                }
                .onDisappear { phase = startPhase }
        }
    }
}

// MARK: - Mini Agent Icon

struct MiniAgentIcon: View {
    let active: Bool
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: size * 0.6))
            .foregroundStyle(active ? Design.statusActive : Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .shadow(color: active ? Design.statusActive.opacity(0.4) : .clear, radius: 2)
    }
}

// MARK: - Shared Helpers


private func shortSessionId(_ id: String) -> String {
    let clean = id.replacingOccurrences(of: "-", with: "")
    if clean.count >= 8 {
        return String(clean.suffix(4))
    }
    return String(id.prefix(4))
}

/// Strip internal directives (::code-comment{}, ::git-*{}, etc.) from message text
/// so they don't leak into the UI preview.
private func stripDirectives(_ text: String) -> String {
    // Match ::directive-name{...} patterns (may span multiple lines)
    // Use a simple approach: remove lines that start with ::word{ or are continuation of a directive
    var result: [String] = []
    var inDirective = false
    var braceDepth = 0

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if inDirective {
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth <= 0 {
                inDirective = false
                braceDepth = 0
            }
            continue
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("::") && trimmed.contains("{") {
            // Count braces to handle single-line vs multi-line directives
            braceDepth = 0
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth > 0 {
                inDirective = true
            }
            // Either way, skip this line
            continue
        }
        result.append(String(line))
    }

    let cleaned = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned
}
