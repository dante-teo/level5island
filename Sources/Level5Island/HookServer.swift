import Foundation
import Network
import os.log
import Level5IslandCore

private let log = Logger(subsystem: Log.subsystem, category: "HookServer")

@MainActor
class HookServer {
    private let appState: AppState
    nonisolated static var socketPath: String { SocketPath.path }
    private var listener: NWListener?
    private var interventionCache = InterventionCache()

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Clean up stale socket
        unlink(HookServer.socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: HookServer.socketPath)

        do {
            listener = try NWListener(using: params)
        } catch {
            log.error("Failed to create NWListener: \(error.localizedDescription)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { @MainActor in
                self.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                log.info("HookServer listening on \(HookServer.socketPath)")
            case .failed(let error):
                log.error("HookServer failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        unlink(HookServer.socketPath)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveAll(connection: connection, accumulated: Data())
    }

    private static let maxPayloadSize = 1_048_576  // 1MB safety limit

    /// Recursively receive all data until EOF, then process
    private func receiveAll(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in

                // On error with no data, just drop the connection
                if error != nil && accumulated.isEmpty && content == nil {
                    connection.cancel()
                    return
                }

                var data = accumulated
                if let content { data.append(content) }

                // Safety: reject oversized payloads
                if data.count > Self.maxPayloadSize {
                    log.warning("Payload too large (\(data.count) bytes), dropping connection")
                    connection.cancel()
                    return
                }

                if isComplete || error != nil {
                    self.processRequest(data: data, connection: connection)
                } else {
                    self.receiveAll(connection: connection, accumulated: data)
                }
            }
        }
    }

    /// Internal tools that are safe to auto-approve without user confirmation.
    private static let autoApproveTools: Set<String> = [
        "TaskCreate", "TaskUpdate", "TaskGet", "TaskList", "TaskOutput", "TaskStop",
        "TodoRead", "TodoWrite",
        "EnterPlanMode",
    ]

    private func processRequest(data: Data, connection: NWConnection) {
        guard let event = HookEvent(from: data) else {
            sendResponse(connection: connection, data: Data("{\"error\":\"parse_failed\"}".utf8))
            return
        }

        if let rawSource = event.rawJSON["_source"] as? String,
           SessionSnapshot.normalizedSupportedSource(rawSource) == nil {
            sendResponse(connection: connection, data: Data("{}".utf8))
            return
        }

        if event.eventName == "PermissionRequest" {
            let sessionId = event.sessionId ?? "default"

            // Auto-approve safe internal tools without showing UI
            if let toolName = event.toolName, Self.autoApproveTools.contains(toolName) {
                let response = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
                sendResponse(connection: connection, data: Data(response.utf8))
                return
            }

            // ExitPlanMode: show notification only, user approves in terminal
            if event.toolName == "ExitPlanMode" {
                log.info("ExitPlanMode intercepted — returning empty response")
                appState.notifyPlanReady(sessionId)
                sendResponse(connection: connection, data: Data("{}".utf8))
                return
            }

            // AskUserQuestion is a question, not a permission — route to QuestionBar
            if event.toolName == "AskUserQuestion" {
                // Check cache for repeated questions (e.g. agent loops, retries)
                let questionText = event.toolInput?["question"] as? String
                    ?? event.toolInput?["questions"].flatMap({ ($0 as? [[String: Any]])?.first?["question"] as? String })
                    ?? ""
                if !questionText.isEmpty,
                   let cached = interventionCache.lookup(sessionId: sessionId, question: questionText) {
                    log.info("Intervention cache hit for session \(sessionId)")
                    // Replay the cached answer
                    let obj: [String: Any] = [
                        "hookSpecificOutput": [
                            "hookEventName": "PermissionRequest",
                            "decision": [
                                "behavior": "allow",
                                "updatedInput": [
                                    "answers": ["answer": cached]
                                ]
                            ] as [String: Any]
                        ] as [String: Any]
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
                    sendResponse(connection: connection, data: data)
                    return
                }

                let requestId = UUID()
                monitorPeerDisconnect(connection: connection, sessionId: sessionId, requestId: requestId)
                Task {
                    let responseBody = await withCheckedContinuation { continuation in
                        appState.handleAskUserQuestion(event, continuation: continuation, requestId: requestId)
                    }
                    // Record the answer in cache for replay
                    if !questionText.isEmpty,
                       let json = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any],
                       let hookOutput = json["hookSpecificOutput"] as? [String: Any],
                       let decision = hookOutput["decision"] as? [String: Any],
                       let behavior = decision["behavior"] as? String, behavior == "allow",
                       let updatedInput = decision["updatedInput"] as? [String: Any],
                       let answers = updatedInput["answers"] as? [String: String],
                       let answer = answers.values.first {
                        self.interventionCache.record(sessionId: sessionId, question: questionText, answer: answer)
                    }
                    self.sendResponse(connection: connection, data: responseBody)
                }
                return
            }
            let permRequestId = UUID()
            monitorPeerDisconnect(connection: connection, sessionId: sessionId, requestId: permRequestId)
            Task {
                let responseBody = await withCheckedContinuation { continuation in
                    appState.handlePermissionRequest(event, continuation: continuation, requestId: permRequestId)
                }
                self.sendResponse(connection: connection, data: responseBody)
            }
        } else if event.eventName == "Notification",
                  QuestionPayload.from(event: event) != nil {
            let questionSessionId = event.sessionId ?? "default"
            let questionRequestId = UUID()
            monitorPeerDisconnect(connection: connection, sessionId: questionSessionId, requestId: questionRequestId)
            Task {
                let responseBody = await withCheckedContinuation { continuation in
                    appState.handleQuestion(event, continuation: continuation, requestId: questionRequestId)
                }
                self.sendResponse(connection: connection, data: responseBody)
            }
        } else {
            appState.handleEvent(event)
            sendResponse(connection: connection, data: Data("{}".utf8))
        }
    }

    /// Per-connection state used by the disconnect monitor.
    /// `responded` flips to true once we've sent the response, so our own
    /// `connection.cancel()` inside `sendResponse` does not masquerade as a
    /// peer disconnect.
    private final class ConnectionContext {
        var responded: Bool = false
    }

    private var connectionContexts: [ObjectIdentifier: ConnectionContext] = [:]

    /// Watch for bridge process disconnect — indicates the bridge process actually died
    /// (e.g. user Ctrl-C'd Claude Code), NOT a normal half-close.
    ///
    /// Previously this used `connection.receive(min:1, max:1)` which triggered on EOF.
    /// But the bridge always does `shutdown(SHUT_WR)` after sending the request (see
    /// Level5IslandBridge/main.swift), which produces an immediate EOF on the read side.
    /// That caused every PermissionRequest to be auto-drained as `deny` before the UI
    /// card was even visible. We now rely on `stateUpdateHandler` transitioning to
    /// `cancelled`/`failed` — which only happens on real socket teardown, not half-close.
    private func monitorPeerDisconnect(connection: NWConnection, sessionId: String, requestId: UUID) {
        let context = ConnectionContext()
        connectionContexts[ObjectIdentifier(connection)] = context

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .cancelled, .failed:
                    if !context.responded {
                        self.appState.handlePeerDisconnect(sessionId: sessionId, requestId: requestId)
                    }
                    self.connectionContexts.removeValue(forKey: ObjectIdentifier(connection))
                default:
                    break
                }
            }
        }
    }

    private func sendResponse(connection: NWConnection, data: Data) {
        // Mark as responded BEFORE cancel() so the disconnect monitor ignores our own teardown.
        if let context = connectionContexts[ObjectIdentifier(connection)] {
            context.responded = true
        }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
