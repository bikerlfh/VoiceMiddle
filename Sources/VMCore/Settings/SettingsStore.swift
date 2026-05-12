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
    }
}
