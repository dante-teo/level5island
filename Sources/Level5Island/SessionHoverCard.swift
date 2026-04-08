import SwiftUI
import Level5IslandCore

/// Hover preview card showing session details in the compact bar.
struct SessionHoverCard: View {
    let session: SessionSnapshot
    let sessionId: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.spacingSM) {
            // Header: project name + status badge
            HStack(spacing: 6) {
                Text(session.displayName)
                    .font(Design.headline(11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                statusBadge
            }

            // Session title if available
            if let title = session.sessionLabel {
                Text(title)
                    .font(Design.caption(9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Latest user message
            if let prompt = session.lastUserPrompt {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(String(prompt.prefix(80)))
                        .font(Design.caption(9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Latest assistant message
            if let msg = session.lastAssistantMessage {
                HStack(alignment: .top, spacing: 4) {
                    ClaudeLogo(size: 8)
                        .frame(width: 10)
                    Text(String(msg.prefix(80)))
                        .font(Design.caption(9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            // Current tool (if running)
            if let tool = session.currentTool {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Design.toolColor(tool))
                        .frame(width: 5, height: 5)
                    Text(tool)
                        .font(Design.mono(9, weight: .medium))
                        .foregroundStyle(Design.toolColor(tool))
                    if let desc = session.toolDescription {
                        Text(String(desc.prefix(40)))
                            .font(Design.mono(8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            // Time since last activity
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 7))
                    .foregroundStyle(.quaternary)
                Text(Design.timeAgo(session.lastActivity) + " ago")
                    .font(Design.caption(8))
                    .foregroundStyle(.quaternary)

                if let model = session.shortModelName {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(model)
                        .font(Design.caption(8))
                        .foregroundStyle(.quaternary)
                }

                if session.activeSubagentCount > 0 {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(session.activeSubagentCount) agent\(session.activeSubagentCount == 1 ? "" : "s")")
                        .font(Design.caption(8))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Design.border, lineWidth: 0.5)
        )
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(Design.caption(8, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusLabel: String {
        switch session.status {
        case .idle:             return session.interrupted ? "interrupted" : "idle"
        case .processing:       return "thinking"
        case .running:          return "running"
        case .waitingApproval:  return "approval"
        case .waitingQuestion:  return "question"
        case .compacting:       return "compacting"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .processing, .running, .compacting:  return Design.statusActive
        case .waitingApproval, .waitingQuestion:   return Design.statusWarning
        case .idle:                                return session.interrupted ? Design.statusError : Design.statusIdle
        }
    }

}
