import AppKit

/// Plays 8-bit sound effects in response to hook events
@MainActor
class SoundManager {
    static let shared = SoundManager()

    private let defaults = UserDefaults.standard

    /// Map event names to 8-bit WAV file names (without extension)
    static let eventSounds: [(event: String, sound: String, key: String, label: String)] = [
        ("SessionStart",      "8bit_start",    SettingsKey.soundSessionStart,   "会话开始"),
        ("Stop",              "8bit_complete",  SettingsKey.soundTaskComplete,   "任务完成"),
        ("PostToolUseFailure","8bit_error",     SettingsKey.soundTaskError,      "任务错误"),
        ("PermissionRequest", "8bit_approval",  SettingsKey.soundApprovalNeeded, "需要审批"),
        ("UserPromptSubmit",  "8bit_submit",    SettingsKey.soundPromptSubmit,   "任务确认"),
    ]

    private var soundCache: [String: NSSound] = [:]

    private init() {
        // Pre-load all sounds into cache
        for entry in Self.eventSounds {
            if let sound = loadSound(entry.sound) {
                soundCache[entry.sound] = sound
            }
        }
    }

    /// Called from AppState.handleEvent() to trigger appropriate sounds
    func handleEvent(_ eventName: String) {
        guard defaults.bool(forKey: SettingsKey.soundEnabled) else { return }
        guard let entry = Self.eventSounds.first(where: { $0.event == eventName }) else { return }
        guard defaults.bool(forKey: entry.key) else { return }
        play(entry.sound)
    }

    /// Play boot sound on app launch
    func playBoot() {
        guard defaults.bool(forKey: SettingsKey.soundEnabled) else { return }
        guard defaults.bool(forKey: SettingsKey.soundBoot) else { return }
        play("8bit_boot")
    }

    /// Preview a specific sound (used by settings UI play buttons)
    func preview(_ soundName: String) {
        play(soundName)
    }

    /// Play a named 8-bit WAV with volume control
    private func play(_ name: String) {
        guard let sound = soundCache[name] ?? loadSound(name) else {
            NSSound.beep()
            return
        }
        if sound.isPlaying { sound.stop() }
        let volume = defaults.integer(forKey: SettingsKey.soundVolume)
        sound.volume = Float(volume) / 100.0
        sound.play()
    }

    /// Resolve the SPM resource bundle, checking both Contents/Resources/ (distribution)
    /// and the app root (SPM debug builds where Bundle.module places it).
    private static let resourceBundle: Bundle? = {
        let bundleName = "Level5Island_Level5Island.bundle"
        // Distribution: .app/Contents/Resources/<bundle>
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName)) {
            return bundle
        }
        // SPM debug builds: Bundle.module (looks at app root)
        return Bundle(url: Bundle.main.bundleURL.appendingPathComponent(bundleName))
    }()

    /// Load a WAV from the SPM resource bundle
    private func loadSound(_ name: String) -> NSSound? {
        guard let bundle = Self.resourceBundle else { return nil }
        if let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Resources") {
            return NSSound(contentsOf: url, byReference: false)
        }
        if let url = bundle.url(forResource: name, withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: false)
        }
        return nil
    }
}
