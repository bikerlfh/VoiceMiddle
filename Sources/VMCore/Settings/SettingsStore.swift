import Foundation

/// Persists user-visible preferences in `UserDefaults`.
///
/// Secrets (API keys, OAuth tokens) do not live here; see ``KeychainService``.
/// The store is intentionally simple: a thin typed facade over the underlying
/// defaults dictionary, with explicit defaults for every key.
///
/// Instances are safe to share across the app because `UserDefaults` itself
/// is thread-safe; we mark the type `@unchecked Sendable` because it stores a
/// reference to `UserDefaults` (a non-`Sendable` class in strict concurrency).
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Pace mode

    public func paceMode(for direction: Direction) -> PaceMode {
        let key = Self.paceKey(for: direction)
        return defaults.string(forKey: key)
            .flatMap(PaceMode.init(rawValue:)) ?? .turnBased
    }

    public func setPaceMode(_ mode: PaceMode, for direction: Direction) {
        defaults.set(mode.rawValue, forKey: Self.paceKey(for: direction))
    }

    // MARK: - Read-only inbound

    public var readOnlyInbound: Bool {
        get { defaults.bool(forKey: Keys.readOnlyInbound) }
        set { defaults.set(newValue, forKey: Keys.readOnlyInbound) }
    }

    // MARK: - Ducking

    public var duckingMode: DuckingMode {
        get {
            defaults.string(forKey: Keys.duckingMode)
                .flatMap(DuckingMode.init(rawValue:)) ?? .duckToLevel
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.duckingMode) }
    }

    public var duckingLevelDB: Double {
        get {
            (defaults.object(forKey: Keys.duckingLevelDB) as? Double) ?? -20
        }
        set { defaults.set(newValue, forKey: Keys.duckingLevelDB) }
    }

    /// Fade duration in milliseconds used when ducking ramps in/out.
    /// Defaults to 80 ms.
    public var duckingFadeMs: Int {
        get {
            (defaults.object(forKey: Keys.duckingFadeMs) as? Int) ?? 80
        }
        set { defaults.set(newValue, forKey: Keys.duckingFadeMs) }
    }

    // MARK: - VAD sensitivity

    /// Per-direction VAD energy threshold. Defaults to 0.005, matching
    /// ``VAD``'s default.
    public func vadSensitivity(for direction: Direction) -> Float {
        let key = direction == .inbound
            ? Keys.vadSensitivityInbound
            : Keys.vadSensitivityOutbound
        if let value = defaults.object(forKey: key) as? Double {
            return Float(value)
        }
        return 0.005
    }

    public func setVADSensitivity(
        _ value: Float, for direction: Direction
    ) {
        let key = direction == .inbound
            ? Keys.vadSensitivityInbound
            : Keys.vadSensitivityOutbound
        defaults.set(Double(value), forKey: key)
    }

    // MARK: - Onboarding

    /// `true` once the user has dismissed the first-launch onboarding
    /// wizard. The wizard is only shown on first launch (or after the
    /// defaults domain is reset).
    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Bundle identifier of the audio process the user picked in the
    /// onboarding wizard as their default capture target. `nil` if the
    /// user skipped that step.
    public var selectedTargetBundleID: String? {
        get { defaults.string(forKey: Keys.selectedTargetBundleID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.selectedTargetBundleID)
            } else {
                defaults.removeObject(forKey: Keys.selectedTargetBundleID)
            }
        }
    }

    // MARK: - General tab

    /// Whether VoiceMiddle should launch automatically at user login.
    /// The actual `SMAppService` registration is performed by the UI
    /// layer (`GeneralTab`) when this value is toggled; this property
    /// is the persisted source of truth.
    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    /// Opacity of the transcript HUD window, clamped to `0.5...1.0` by
    /// the UI. Defaults to `0.85`.
    public var hudOpacity: Double {
        get {
            (defaults.object(forKey: Keys.hudOpacity) as? Double) ?? 0.85
        }
        set { defaults.set(newValue, forKey: Keys.hudOpacity) }
    }

    /// Persisted virtual key code for the user's custom session-toggle
    /// global hotkey. `nil` means "use the built-in default if
    /// Accessibility permission is granted". Stored as `NSNumber` so
    /// `nil` round-trips through `UserDefaults`.
    public var globalHotkeyKeyCode: UInt16? {
        get {
            let value = defaults.object(forKey: Keys.globalHotkeyKeyCode)
            guard let number = value as? NSNumber else { return nil }
            return number.uint16Value
        }
        set {
            if let newValue {
                defaults.set(
                    NSNumber(value: newValue),
                    forKey: Keys.globalHotkeyKeyCode
                )
            } else {
                defaults.removeObject(forKey: Keys.globalHotkeyKeyCode)
            }
        }
    }

    /// Persisted modifier-flags bitmask for the user's custom
    /// session-toggle global hotkey. Paired with
    /// ``globalHotkeyKeyCode``.
    public var globalHotkeyModifierFlags: UInt? {
        get {
            let value = defaults.object(
                forKey: Keys.globalHotkeyModifierFlags
            )
            guard let number = value as? NSNumber else { return nil }
            return number.uintValue
        }
        set {
            if let newValue {
                defaults.set(
                    NSNumber(value: newValue),
                    forKey: Keys.globalHotkeyModifierFlags
                )
            } else {
                defaults.removeObject(
                    forKey: Keys.globalHotkeyModifierFlags
                )
            }
        }
    }

    // MARK: - Languages tab

    /// BCP-47 language code of the audio coming from the other party
    /// (what the inbound pipeline should transcribe). Defaults to `"en"`.
    public var sourceLanguageCode: String {
        get { defaults.string(forKey: Keys.sourceLanguageCode) ?? "en" }
        set { defaults.set(newValue, forKey: Keys.sourceLanguageCode) }
    }

    /// BCP-47 language code the user wants translations rendered into
    /// (and the language the outbound pipeline speaks in). Defaults to
    /// `"es"`.
    public var targetLanguageCode: String {
        get { defaults.string(forKey: Keys.targetLanguageCode) ?? "es" }
        set { defaults.set(newValue, forKey: Keys.targetLanguageCode) }
    }

    /// ElevenLabs voice ID used for outbound TTS. Default is Rachel
    /// (`21m00Tcm4TlvDq8ikWAM`), a public ElevenLabs voice.
    public var voiceID: String {
        get {
            defaults.string(forKey: Keys.voiceID) ?? "21m00Tcm4TlvDq8ikWAM"
        }
        set { defaults.set(newValue, forKey: Keys.voiceID) }
    }

    // MARK: - Translation tab

    /// Identifier of the translation engine the user wants to use.
    /// Free-form string so we can introduce new engines without touching
    /// the storage layer. Defaults to `"deepL"`.
    public var translatorIdentifier: String {
        get {
            defaults.string(forKey: Keys.translatorIdentifier)
                ?? "deepL"
        }
        set { defaults.set(newValue, forKey: Keys.translatorIdentifier) }
    }

    /// Model name to use when the selected translator is Claude.
    public var claudeModel: String {
        get {
            defaults.string(forKey: Keys.claudeModel)
                ?? "claude-haiku-4-5-20251001"
        }
        set { defaults.set(newValue, forKey: Keys.claudeModel) }
    }

    /// Model name to use when the selected translator is OpenAI/GPT.
    public var openAIModel: String {
        get {
            defaults.string(forKey: Keys.openAIModel) ?? "gpt-4o-mini"
        }
        set { defaults.set(newValue, forKey: Keys.openAIModel) }
    }

    // MARK: - Outbound

    /// Whether the outbound (you → other party) pipeline should run alongside
    /// the inbound one. When enabled, translated audio is written into the
    /// Core Audio device matched by ``outboundDeviceName``.
    public var outboundEnabled: Bool {
        get { defaults.bool(forKey: Keys.outboundEnabled) }
        set { defaults.set(newValue, forKey: Keys.outboundEnabled) }
    }

    /// Substring match (case-insensitive) used to locate the outbound output
    /// device. Defaults to `"BlackHole 2ch"`, the open-source virtual audio
    /// device installed via `brew install --cask blackhole-2ch`.
    public var outboundDeviceName: String {
        get {
            defaults.string(forKey: Keys.outboundDeviceName)
                ?? "BlackHole 2ch"
        }
        set { defaults.set(newValue, forKey: Keys.outboundDeviceName) }
    }

    // MARK: - Privacy tab

    /// Whether session transcripts should be persisted to disk under
    /// `~/Library/Application Support/VoiceMiddle/Transcripts/`. Storage
    /// wiring lands in a follow-up task; this is the source of truth.
    public var saveTranscripts: Bool {
        get { defaults.bool(forKey: Keys.saveTranscripts) }
        set { defaults.set(newValue, forKey: Keys.saveTranscripts) }
    }

    // MARK: - Keys

    private static func paceKey(for direction: Direction) -> String {
        switch direction {
        case .inbound:  return Keys.paceInbound
        case .outbound: return Keys.paceOutbound
        }
    }

    private enum Keys {
        static let paceInbound             = "vm.settings.paceInbound"
        static let paceOutbound            = "vm.settings.paceOutbound"
        static let readOnlyInbound         = "vm.settings.readOnlyInbound"
        static let duckingMode             = "vm.settings.duckingMode"
        static let duckingLevelDB          = "vm.settings.duckingLevelDB"
        static let hasCompletedOnboarding  = "vm.settings.hasCompletedOnboarding"
        static let selectedTargetBundleID  = "vm.settings.selectedTargetBundleID"
        static let launchAtLogin           = "vm.settings.launchAtLogin"
        static let hudOpacity              = "vm.settings.hudOpacity"
        static let globalHotkeyKeyCode     = "vm.settings.globalHotkeyKeyCode"
        static let globalHotkeyModifierFlags = "vm.settings.globalHotkeyModifierFlags"
        static let sourceLanguageCode      = "vm.settings.sourceLanguageCode"
        static let targetLanguageCode      = "vm.settings.targetLanguageCode"
        static let voiceID                 = "vm.settings.voiceID"
        static let translatorIdentifier    = "vm.settings.translatorIdentifier"
        static let claudeModel             = "vm.settings.claudeModel"
        static let openAIModel             = "vm.settings.openAIModel"
        static let saveTranscripts         = "vm.settings.saveTranscripts"
        static let vadSensitivityInbound   = "vm.settings.vadSensitivityInbound"
        static let vadSensitivityOutbound  = "vm.settings.vadSensitivityOutbound"
        static let duckingFadeMs           = "vm.settings.duckingFadeMs"
        static let outboundEnabled         = "vm.settings.outboundEnabled"
        static let outboundDeviceName      = "vm.settings.outboundDeviceName"
    }
}
