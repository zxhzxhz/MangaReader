import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let cacheLimitKey = "cacheLimitGB"
    static let globalProfileKey = "globalProfileID"

    let db: AppDatabase

    @Published var cacheLimitGB: Double = 5
    @Published var globalProfileID: UUID?

    init(db: AppDatabase) {
        self.db = db
        reload()
    }

    func reload() {
        if let raw = db.setting(Self.cacheLimitKey), let value = Double(raw) {
            cacheLimitGB = value
        }
        if let raw = db.setting(Self.globalProfileKey), let uuid = UUID(uuidString: raw) {
            globalProfileID = uuid
        }
    }

    func setCacheLimit(_ value: Double) async {
        cacheLimitGB = value
        db.setSetting(String(value), forKey: Self.cacheLimitKey)
        await CacheManager.shared.setLimit(gigabytes: value)
        await CacheManager.shared.enforceLimit()
    }

    func setGlobalProfile(_ id: UUID?) {
        globalProfileID = id
        db.setSetting(id?.uuidString ?? "", forKey: Self.globalProfileKey)
    }
}
