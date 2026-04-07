import Foundation
import Darwin

public enum SocketPath {
    public static var path: String {
        if let env = ProcessInfo.processInfo.environment["LEVEL5ISLAND_SOCKET_PATH"] {
            return env
        }
        return "/tmp/level5island-\(getuid()).sock"
    }
}
