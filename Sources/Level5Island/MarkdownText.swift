import SwiftUI
import Level5IslandCore

/// Renders inline markdown using the shared `ChatMessageTextFormatter` cache.
struct MarkdownText: View {
    let text: String
    var color: Color = .primary
    var fontSize: CGFloat = 11

    private var renderedText: AttributedString {
        var result = ChatMessageTextFormatter.inlineMarkdown(text)
        result.foregroundColor = color
        result.font = Design.body(fontSize)
        return result
    }

    var body: some View {
        Text(renderedText)
    }
}
