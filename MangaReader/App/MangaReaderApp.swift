import SwiftUI

@main
struct MangaReaderApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(model)
                .environmentObject(model.profileStore)
                .environmentObject(model.settings)
                .task { await model.scanLibrary() }
        }
    }
}
