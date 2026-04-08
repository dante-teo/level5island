import Foundation

public enum ChatMessageTextFormatter {
    private static var markdownCache: [String: AttributedString] = [:]
    private static var markdownInsertOrder: [String] = []
    private static let markdownCacheLimit = 128

    public static func displayText(for message: ChatMessage) -> AttributedString {
        message.isUser ? literalText(message.text) : inlineMarkdown(message.text)
    }

    public static func literalText(_ text: String) -> AttributedString {
        AttributedString(text)
    }

    public static func inlineMarkdown(_ text: String) -> AttributedString {
        if let cached = markdownCache[text] { return cached }

        let result: AttributedString
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            result = attr
        } else {
            result = AttributedString(text)
        }

        if markdownCache.count >= markdownCacheLimit {
            let evictCount = markdownCacheLimit / 2
            for key in markdownInsertOrder.prefix(evictCount) {
                markdownCache.removeValue(forKey: key)
            }
            markdownInsertOrder.removeFirst(evictCount)
        }
        markdownCache[text] = result
        markdownInsertOrder.append(text)
        return result
    }
}
