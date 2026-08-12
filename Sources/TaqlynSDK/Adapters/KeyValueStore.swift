import Foundation

/// Local prefs for resolved-once flag and small SDK state.
public protocol KeyValueStore: AnyObject {
    func getBoolean(_ key: String, default defaultValue: Bool) -> Bool
    func putBoolean(_ key: String, _ value: Bool)
    func getString(_ key: String, default defaultValue: String?) -> String?
    func putString(_ key: String, _ value: String?)
    func remove(_ key: String)
}

/// In-memory store for unit tests.
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var booleans: [String: Bool] = [:]
    private var strings: [String: String?] = [:]

    public init() {}

    public func getBoolean(_ key: String, default defaultValue: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return booleans[key] ?? defaultValue
    }

    public func putBoolean(_ key: String, _ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        booleans[key] = value
    }

    public func getString(_ key: String, default defaultValue: String? = nil) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if strings.keys.contains(key) {
            return strings[key] ?? nil
        }
        return defaultValue
    }

    public func putString(_ key: String, _ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            strings[key] = value
        } else {
            strings.removeValue(forKey: key)
        }
    }

    public func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        booleans.removeValue(forKey: key)
        strings.removeValue(forKey: key)
    }
}

/// UserDefaults-backed store (suite optional for App Group later).
/// Named "secure-store" adapter in architecture — local prefs for resolved-once.
public final class UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            defaults = suite
        } else {
            defaults = .standard
        }
    }

    public func getBoolean(_ key: String, default defaultValue: Bool = false) -> Bool {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    public func putBoolean(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
    }

    public func getString(_ key: String, default defaultValue: String? = nil) -> String? {
        if let value = defaults.string(forKey: key) {
            return value
        }
        return defaultValue
    }

    public func putString(_ key: String, _ value: String?) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}

public enum SdkStoreKeys {
    public static let deferredResolved = "taqlyn.deferred_resolved"
}
