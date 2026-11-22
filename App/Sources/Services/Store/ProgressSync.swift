import Foundation
import Security

/// Keeps the family's progress when the app is deleted and installed again, or moved to a new
/// iPhone (ADR-0023): players and their review boxes and scores, which questions the family has
/// had, bought questions and today's usage. No account and no identifier of ours: the backup
/// lives in the family's own iCloud (key-value storage) and in this iPhone's Keychain, which
/// iOS keeps after the app is deleted.
@MainActor
final class ProgressSync {
    struct Backup: Codable {
        var version = 1
        var allowance = AllowanceStore.State()
        var players: [PlayerStore.Snapshot] = []
        /// Always empty: players can't be deleted any more (ADR-0025). Still written so builds
        /// before 0.3.6 can read the backup.
        var deletedPlayers: Set<String> = []
        var savedAt = Date.now
    }

    private let allowance: AllowanceStore
    private let players: PlayerStore
    private let storages: [any BackupStorage]
    private var pendingSave: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(allowance: AllowanceStore, players: PlayerStore, storages: [any BackupStorage]) {
        self.allowance = allowance
        self.players = players
        self.storages = storages
    }

    static func live(allowance: AllowanceStore, players: PlayerStore) -> ProgressSync {
        ProgressSync(allowance: allowance, players: players,
                     storages: [ICloudKeyValueStorage(), KeychainStorage()])
    }

    /// Merges every saved copy in, then keeps them up to date as things change.
    func start() {
        restore()
        allowance.onChange = { [weak self] in self?.scheduleSave() }
        players.onChange = { [weak self] in self?.scheduleSave() }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        }
        save()
    }

    /// Brings in every copy it can find (unions and latest answers: nothing is lost).
    func restore() {
        let decoder = JSONDecoder()
        for storage in storages {
            guard let data = storage.read(), let backup = try? decoder.decode(Backup.self, from: data) else { continue }
            allowance.merge(backup.allowance)
            players.merge(backup.players)
        }
    }

    /// Saves shortly after a change (several changes in a row are written once).
    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Deletes every saved copy (the tester reset). Changes after this are saved as usual.
    func eraseBackup() {
        pendingSave?.cancel()
        for storage in storages { storage.erase() }
    }

    func save() {
        let backup = Backup(allowance: allowance.state, players: players.snapshot())
        guard let data = try? JSONEncoder().encode(backup) else { return }
        for storage in storages { storage.write(data) }
    }
}

/// Somewhere a backup can be kept.
@MainActor
protocol BackupStorage {
    func read() -> Data?
    func write(_ data: Data)
    func erase()
}

/// The family's own iCloud (key-value storage, up to 1 MB). Follows their Apple ID to a new
/// iPhone or a reinstall. Does nothing if iCloud is off.
@MainActor
struct ICloudKeyValueStorage: BackupStorage {
    static let key = "progress.v1"
    private let store = NSUbiquitousKeyValueStore.default

    init() { store.synchronize() }

    func read() -> Data? { store.data(forKey: Self.key) }

    func write(_ data: Data) {
        // Key-value storage holds 1 MB in all; the Keychain copy still has everything.
        guard data.count < 900_000 else { return }
        store.set(data, forKey: Self.key)
    }

    func erase() { store.removeObject(forKey: Self.key) }
}

/// This iPhone's Keychain, which iOS keeps when the app is deleted, so reinstalling doesn't
/// start over even with iCloud off. Stays on this device (not synced, not backed up elsewhere).
@MainActor
struct KeychainStorage: BackupStorage {
    var service = "com.jcena.buckleupquiz.progress"
    var account = "backup.v1"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(_ data: Data) {
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func erase() { SecItemDelete(query as CFDictionary) }
}
