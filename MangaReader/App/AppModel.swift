import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let db: AppDatabase
    let scanner: LibraryScanner
    let archiveService: ArchiveService
    let pageSource: PageSourceService
    let fileOperations: FileOperationsService
    let coverService: CoverService
    let upscaleService: UpscaleService
    let settings: SettingsStore
    let profileStore: OnnxProfileStore

    @Published var items: [LibraryItem] = []
    @Published var errorMessage: String?
    @Published var isScanning = false

    init() {
        do {
            self.db = try AppDatabase.open()
        } catch {
            fatalError("Unable to open MangaReader database: \(error)")
        }
        let archive = ArchiveService()
        self.archiveService = archive
        let pages = PageSourceService(db: self.db)
        self.pageSource = pages
        self.scanner = LibraryScanner(db: self.db)
        self.fileOperations = FileOperationsService(db: self.db, archiveService: archive)
        self.coverService = CoverService(db: self.db, pageSource: pages)
        self.upscaleService = UpscaleService()
        self.settings = SettingsStore(db: self.db)
        self.profileStore = OnnxProfileStore(db: self.db)
        refresh()
    }

    func refresh() {
        items = (try? db.allItems()) ?? []
    }

    func children(of parent: String?) -> [LibraryItem] {
        let prefix = parent.map { $0.isEmpty ? "" : $0 + "/" } ?? ""
        return items.filter { item in
            let rest: String
            if prefix.isEmpty {
                rest = item.relativePath
            } else if item.relativePath.hasPrefix(prefix) {
                rest = String(item.relativePath.dropFirst(prefix.count))
            } else {
                rest = ""
            }
            return !rest.isEmpty && !rest.contains("/")
        }
        .sorted { NaturalSort.compare($0.title, $1.title) == .orderedAscending }
    }

    func scanLibrary() async {
        isScanning = true
        defer { isScanning = false }
        do {
            try await scanner.scan()
            refresh()
            settings.reload()
            profileStore.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func globalProfile() -> ModelProfile? {
        guard let id = settings.globalProfileID else { return nil }
        return profileStore.profiles.first { $0.id == id }
    }
}
