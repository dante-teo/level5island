import SwiftUI
import Level5IslandCore

/// Enhanced question form: multi-select, secret input, "other" free-text, and markdown.
struct QuestionFormView: View {
    let question: QuestionPayload
    let sessionSource: String?
    let sessionContext: String?
    let queuePosition: Int
    let queueTotal: Int
    let onAnswer: (String) -> Void
    let onSkip: () -> Void

    @State private var textInput = ""
    @State private var selectedIndices: Set<Int> = []
    @State private var otherText = ""
    @State private var otherEnabled = false
    @FocusState private var isFocused: Bool

    private let accent = Design.statusQuestion

    private var hasOptions: Bool {
        guard let opts = question.options else { return false }
        return !opts.isEmpty
    }

    var body: some View {
        VStack(spacing: Design.spacingSM) {
            if sessionSource != nil || sessionContext != nil {
                HStack(spacing: 5) {
                    if sessionSource != nil { ClaudeLogo(size: 12) }
                    if let cwd = sessionContext {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text((cwd as NSString).lastPathComponent)
                            .font(Design.caption(9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            if let header = question.header, !header.isEmpty {
                HStack {
                    MarkdownText(text: header, color: .secondary, fontSize: 10)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                MarkdownText(text: question.question, color: .primary, fontSize: 11)
                    .lineLimit(3)
                if queueTotal > 1 {
                    Text("\(queuePosition)/\(queueTotal)")
                        .font(Design.caption(9, weight: .bold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
            }
            .padding(.horizontal, 14)

            if hasOptions && question.allowsMultiple {
                multiSelectGrid
            } else if hasOptions {
                singleSelectList
            } else {
                textField(secure: question.isSecret)
            }

            if hasOptions && question.allowsOther {
                otherField
            }

            actionButtons
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Design.statusQuestion.opacity(0.35)
                .frame(height: 1)
                .blur(radius: 2)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - Input Variants

    @ViewBuilder
    private func textField(secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(L10n.shared["type_answer"], text: $textInput)
                    .focused($isFocused)
                    .onSubmit { submitIfValid() }
            } else {
                TextField(L10n.shared["type_answer"], text: $textInput)
                    .focused($isFocused)
                    .onSubmit { submitIfValid() }
            }
        }
        .textFieldStyle(.plain)
        .font(Design.mono(10.5))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 14)
    }

    private var multiSelectGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { idx, option in
                let isSelected = selectedIndices.contains(idx)
                Button {
                    if isSelected { selectedIndices.remove(idx) }
                    else { selectedIndices.insert(idx) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? accent : .secondary)
                        Text(option)
                            .font(Design.body(10.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? accent.opacity(0.12) : .white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? accent.opacity(0.3) : .white.opacity(0.08), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    private var singleSelectList: some View {
        VStack(spacing: 4) {
            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { idx, option in
                let desc = question.descriptions?.indices.contains(idx) == true ? question.descriptions?[idx] : nil
                OptionRow(index: idx + 1, label: option, description: desc, isSelected: selectedIndices.contains(idx), accent: accent) {
                    selectedIndices = [idx]
                    onAnswer(option)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var otherField: some View {
        HStack(spacing: 6) {
            Button {
                otherEnabled.toggle()
                if !otherEnabled { otherText = "" }
            } label: {
                Image(systemName: otherEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(otherEnabled ? accent : .secondary)
            }
            .buttonStyle(.plain)

            if otherEnabled {
                TextField(L10n.shared["type_answer"], text: $otherText)
                    .textFieldStyle(.plain)
                    .font(Design.mono(10.5))
                    .foregroundStyle(.primary)
                    .onSubmit { submitIfValid() }
            } else {
                Text("Other\u{2026}")
                    .font(Design.body(10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 14)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            PixelButton(
                label: L10n.shared["skip"],
                fg: .secondary,
                bg: .white.opacity(0.06),
                border: .white.opacity(0.12),
                action: onSkip
            )
            if !hasOptions || question.allowsMultiple || question.isSecret || question.allowsOther {
                PixelButton(
                    label: L10n.shared["submit"],
                    fg: .white,
                    bg: Design.statusActive.opacity(0.5),
                    border: Design.statusActive.opacity(0.4),
                    action: { submitIfValid() }
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private func submitIfValid() {
        if question.isSecret || (!hasOptions && !question.allowsOther) {
            guard !textInput.isEmpty else { return }
            onAnswer(textInput)
        } else if question.allowsMultiple {
            guard let opts = question.options else { return }
            var answers = selectedIndices.sorted().compactMap { idx in
                opts.indices.contains(idx) ? opts[idx] : nil
            }
            if otherEnabled && !otherText.isEmpty { answers.append(otherText) }
            guard !answers.isEmpty else { return }
            onAnswer(answers.joined(separator: ", "))
        } else if otherEnabled && !otherText.isEmpty {
            onAnswer(otherText)
        }
    }
}
