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

    // MARK: - Keys

    private static func paceKey(for direction: Direction) -> String {
        switch direction {
        case .inbound:  return Keys.paceInbound
        case .outbound: return Keys.paceOutbound
        }
    }

    private enum Keys {
        static let paceInbound     = "vm.settings.paceInbound"
        static let paceOutbound    = "vm.settings.paceOutbound"
        static let readOnlyInbound = "vm.settings.readOnlyInbound"
        static let duckingMode     = "vm.settings.duckingMode"
        static let duckingLevelDB  = "vm.settings.duckingLevelDB"
    }
}
