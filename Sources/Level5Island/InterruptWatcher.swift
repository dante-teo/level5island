import Foundation
import os.log

private let log = Logger(subsystem: Log.subsystem, category: "InterruptWatcher")

/// Watches session JSONL files for interrupt indicators as a fallback
/// detection path when the bridge/hook doesn't fire on Ctrl+C.
@MainActor
final class InterruptWatcherManager {
    static let shared = InterruptWatcherManager()
    private var watchers: [String: JSONLWatcher] = [:]
    var onInterruptDetected: ((String) -> Void)?

    func startWatching(sessionId: String, cwd: String) {
        guard watchers[sessionId] == nil else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectDir = cwd.claudeProjectDirEncoded()
        let path = "\(home)/.claude/projects/\(projectDir)/\(sessionId).jsonl"

        guard FileManager.default.fileExists(atPath: path) else { return }

        let watcher = JSONLWatcher(path: path, sessionId: sessionId) { [weak self] sid in
            Task { @MainActor in
                self?.stopWatching(sessionId: sid)
                self?.onInterruptDetected?(sid)
            }
        }
        watchers[sessionId] = watcher
        watcher.start()
    }

    func stopWatching(sessionId: String) {
        watchers[sessionId]?.stop()
        watchers.removeValue(forKey: sessionId)
    }

    func stopAll() {
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
    }
}

final class JSONLWatcher {
    private let path: String
    private let sessionId: String
    private let onInterrupt: (String) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var lastOffset: UInt64 = 0

    private static let interruptPatterns = [
        "Interrupted by user",
        "interrupted by user",
        "user doesn't want to proceed",
        "[Request interrupted by user",
    ]

    init(path: String, sessionId: String, onInterrupt: @escaping (String) -> Void) {
        self.path = path
        self.sessionId = sessionId
        self.onInterrupt = onInterrupt
    }

    func start() {
        if let handle = FileHandle(forReadingAtPath: path) {
            handle.seekToEndOfFile()
            lastOffset = handle.offsetInFile
            handle.closeFile()
        }

        fileDescriptor = open(path, O_RDONLY | O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main
        )

        src.setEventHandler { [weak self] in
            self?.handleFileChange()
        }

        src.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func handleFileChange() {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: lastOffset)
        let newData = handle.readDataToEndOfFile()
        lastOffset = handle.offsetInFile

        guard !newData.isEmpty,
              let text = String(data: newData, encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            if checkForInterrupt(line: line) {
                log.info("Interrupt detected via JSONL for \(self.sessionId)")
                onInterrupt(sessionId)
                return
            }
        }
    }

    private func checkForInterrupt(line: String) -> Bool {
        for pattern in Self.interruptPatterns {
            if line.contains(pattern) { return true }
        }
        if line.contains("\"interrupted\""),
           let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["interrupted"] as? Bool == true {
            return true
        }
        return false
    }
}
