import Foundation
import Level5IslandCore

struct PermissionRequest {
    let id: UUID
    let event: HookEvent
    let continuation: CheckedContinuation<Data, Never>

    init(event: HookEvent, continuation: CheckedContinuation<Data, Never>, id: UUID = UUID()) {
        self.id = id
        self.event = event
        self.continuation = continuation
    }
}

struct QuestionRequest {
    let id: UUID
    let event: HookEvent
    let question: QuestionPayload
    let continuation: CheckedContinuation<Data, Never>
    /// true when converted from AskUserQuestion PermissionRequest
    let isFromPermission: Bool

    init(event: HookEvent, question: QuestionPayload, continuation: CheckedContinuation<Data, Never>, isFromPermission: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.event = event
        self.question = question
        self.continuation = continuation
        self.isFromPermission = isFromPermission
    }
}
