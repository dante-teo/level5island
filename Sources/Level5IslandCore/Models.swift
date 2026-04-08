import Foundation

public enum AgentStatus: Equatable, Sendable {
    case idle
    case processing
    case running          // active tool execution
    case waitingApproval  // permission blocked
    case waitingQuestion  // question blocked
    case compacting       // context compression

    /// Whether the status needs user attention (approval or question).
    public var needsAttention: Bool {
        self == .waitingApproval || self == .waitingQuestion
    }

    /// Whether the status represents active work (processing or running).
    public var isActive: Bool {
        self == .processing || self == .running
    }

    /// Validates whether a transition to `next` is allowed.
    public func canTransition(to next: AgentStatus) -> Bool {
        if self == next { return next == .waitingApproval }
        switch (self, next) {
        case (.idle, .processing), (.idle, .running), (.idle, .waitingApproval),
             (.idle, .waitingQuestion), (.idle, .compacting):
            return true
        case (.processing, .running), (.processing, .idle), (.processing, .waitingApproval),
             (.processing, .waitingQuestion), (.processing, .compacting):
            return true
        case (.running, .processing), (.running, .idle), (.running, .waitingApproval),
             (.running, .waitingQuestion):
            return true
        case (.waitingApproval, .processing), (.waitingApproval, .idle):
            return true
        case (.waitingQuestion, .processing), (.waitingQuestion, .idle):
            return true
        case (.compacting, .processing), (.compacting, .idle), (.compacting, .waitingApproval):
            return true
        default:
            return false
        }
    }
}

public struct HookEvent {
    public let eventName: String
    public let sessionId: String?
    public let toolName: String?
    public let agentId: String?
    public let toolInput: [String: Any]?
    public let rawJSON: [String: Any]  // Full payload for event-specific fields

    public init?(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = json["hook_event_name"] as? String else {
            return nil
        }
        self.eventName = eventName
        self.sessionId = json["session_id"] as? String
        self.toolName = json["tool_name"] as? String
        self.toolInput = json["tool_input"] as? [String: Any]
        self.agentId = json["agent_id"] as? String
        self.rawJSON = json
    }

    public var toolDescription: String? {
        // Try tool_input fields first
        if let input = toolInput {
            if let command = input["command"] as? String { return command }
            if let filePath = input["file_path"] as? String { return (filePath as NSString).lastPathComponent }
            if let pattern = input["pattern"] as? String { return pattern }
            if let prompt = input["prompt"] as? String { return String(prompt.prefix(40)) }
        }
        // Fall back to top-level fields
        if let msg = rawJSON["message"] as? String { return msg }
        if let agentType = rawJSON["agent_type"] as? String { return agentType }
        if let prompt = rawJSON["prompt"] as? String { return String(prompt.prefix(40)) }
        return nil
    }
}

public struct SubagentState {
    public let agentId: String
    public let agentType: String
    public var status: AgentStatus = .running
    public var currentTool: String?
    public var toolDescription: String?
    public var startTime: Date = Date()
    public var lastActivity: Date = Date()

    public init(agentId: String, agentType: String) {
        self.agentId = agentId
        self.agentType = agentType
    }
}

public struct ToolHistoryEntry: Identifiable {
    public let id = UUID()
    public let tool: String
    public let description: String?
    public let timestamp: Date
    public let success: Bool
    public let agentType: String?  // nil = main thread

    public init(tool: String, description: String?, timestamp: Date, success: Bool, agentType: String?) {
        self.tool = tool
        self.description = description
        self.timestamp = timestamp
        self.success = success
        self.agentType = agentType
    }
}

public struct ChatMessage: Identifiable {
    public let id = UUID()
    public let isUser: Bool
    public let text: String

    public init(isUser: Bool, text: String) {
        self.isUser = isUser
        self.text = text
    }
}

public struct QuestionPayload {
    public let question: String
    public let options: [String]?
    public let descriptions: [String]?
    public let header: String?
    public let isSecret: Bool         // secure text field
    public let allowsMultiple: Bool   // checkbox multi-select
    public let allowsOther: Bool      // "other" free-text option

    public init(
        question: String,
        options: [String]?,
        descriptions: [String]? = nil,
        header: String? = nil,
        isSecret: Bool = false,
        allowsMultiple: Bool = false,
        allowsOther: Bool = false
    ) {
        self.question = question
        self.options = options
        self.descriptions = descriptions
        self.header = header
        self.isSecret = isSecret
        self.allowsMultiple = allowsMultiple
        self.allowsOther = allowsOther
    }

    /// Try to extract question from a Notification hook event
    public static func from(event: HookEvent) -> QuestionPayload? {
        if let question = event.rawJSON["question"] as? String {
            let options = event.rawJSON["options"] as? [String]
            let isSecret = event.rawJSON["is_secret"] as? Bool ?? false
            let allowsMultiple = event.rawJSON["allows_multiple"] as? Bool ?? false
            let allowsOther = event.rawJSON["allows_other"] as? Bool ?? false
            return QuestionPayload(
                question: question,
                options: options,
                isSecret: isSecret,
                allowsMultiple: allowsMultiple,
                allowsOther: allowsOther
            )
        }
        return nil
    }
}
