import Foundation
import GRDB

struct AppDatabase {
    let dbQueue: DatabaseQueue

    init(_ dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    static func open() throws -> AppDatabase {
        try AppPaths.prepare()
        let dbQueue = try DatabaseQueue(path: AppPaths.databaseURL.path)
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: LibraryItem.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("relativePath", .text).notNull().unique()
                table.column("fingerprint", .text).notNull()
                table.column("title", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("mixedResolution", .text).notNull().defaults(to: MixedResolution.pending.rawValue)
                table.column("coverKey", .text)
                table.column("progressPage", .integer).notNull().defaults(to: 0)
                table.column("pageCount", .integer)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: ModelProfile.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("modelFileName", .text).notNull()
                table.column("scale", .integer).notNull()
                table.column("inputName", .text).notNull()
                table.column("outputName", .text).notNull()
                table.column("tileSize", .integer).notNull()
                table.column("overlap", .integer).notNull()
                table.column("colorSpace", .text).notNull()
                table.column("normalization", .text).notNull()
                table.column("alphaMode", .text).notNull()
                table.column("denoiseLevel", .integer)
                table.column("executionProvider", .text).notNull()
                table.column("isTemplate", .boolean).notNull().defaults(to: false)
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "appSetting") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: LibraryItem.databaseTableName) { table in
                table.add(column: "directImageCount", .integer).notNull().defaults(to: 0)
                table.add(column: "isVirtual", .boolean).notNull().defaults(to: false)
            }
        }

        try migrator.migrate(dbQueue)
        return AppDatabase(dbQueue)
    }

    func allItems() throws -> [LibraryItem] {
        try dbQueue.read { db in
            try LibraryItem.fetchAll(db)
        }
    }

    func item(byRelativePath path: String) throws -> LibraryItem? {
        try dbQueue.read { db in
            try LibraryItem.filter(Column("relativePath") == path).fetchOne(db)
        }
    }

    func items(under path: String) throws -> [LibraryItem] {
        try dbQueue.read { db in
            let prefix = path.isEmpty ? "" : path + "/"
            return try LibraryItem
                .filter(Column("relativePath").like(prefix + "%"))
                .fetchAll(db)
        }
    }

    func items(atOrUnder path: String) throws -> [LibraryItem] {
        try allItems().filter {
            $0.relativePath == path || $0.relativePath.hasPrefix(path + "/")
        }
    }

    func updateRelativePathPrefix(from oldPrefix: String, to newPrefix: String) throws {
        try dbQueue.write { db in
            let oldItems = try LibraryItem.fetchAll(db)
            for item in oldItems {
                var updated = item
                if oldPrefix.isEmpty {
                    updated.relativePath = newPrefix.isEmpty
                        ? item.relativePath
                        : newPrefix + "/" + item.relativePath
                } else if item.relativePath == oldPrefix {
                    updated.relativePath = newPrefix
                } else if item.relativePath.hasPrefix(oldPrefix + "/") {
                    let suffix = String(item.relativePath.dropFirst(oldPrefix.count + 1))
                    updated.relativePath = newPrefix.isEmpty ? suffix : newPrefix + "/" + suffix
                } else {
                    continue
                }
                updated.updatedAt = Date()
                try updated.save(db)
            }
        }
    }

    func item(byID id: UUID) throws -> LibraryItem? {
        try dbQueue.read { db in
            try LibraryItem.fetchOne(db, key: id)
        }
    }

    func save(_ item: LibraryItem) throws {
        try dbQueue.write { db in
            try item.save(db)
        }
    }

    func delete(_ item: LibraryItem) throws {
        try dbQueue.write { db in
            try item.delete(db)
        }
    }

    func profiles() throws -> [ModelProfile] {
        try dbQueue.read { db in
            try ModelProfile.fetchAll(db)
        }
    }

    func save(_ profile: ModelProfile) throws {
        try dbQueue.write { db in
            try profile.save(db)
        }
    }

    func delete(_ profile: ModelProfile) throws {
        try dbQueue.write { db in
            try profile.delete(db)
        }
    }

    func setting(_ key: String) -> String? {
        try? dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM appSetting WHERE key = ?", arguments: [key])
        }
    }

    func setSetting(_ value: String, forKey key: String) {
        try? dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO appSetting (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [key, value]
            )
        }
    }
}

extension AppDatabase: @unchecked Sendable {}
