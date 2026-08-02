import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var profileStore: OnnxProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var cacheLimit = 5.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Enhancement") {
                    NavigationLink("ONNX Models") {
                        ModelProfilesView()
                    }
                    if profileStore.profiles.isEmpty {
                        LabeledContent("Default Model", value: "None")
                    } else {
                        Picker("Default Model", selection: Binding<UUID?>(
                            get: { settingsStore.globalProfileID },
                            set: { settingsStore.setGlobalProfile($0) }
                        )) {
                            Text("None").tag(nil as UUID?)
                            ForEach(profileStore.profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                    }
                }

                Section("Cache") {
                    Stepper(
                        value: $cacheLimit,
                        in: 1...50,
                        step: 1
                    ) {
                        Text("Cache Limit: \(Int(cacheLimit)) GB")
                    }
                    Button("Clear Derived Cache") {
                        Task {
                            await CacheManager.shared.purgeAll()
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    LabeledContent("Build", value: "1")
                    NavigationLink("Third-Party Notices") {
                        ThirdPartyNoticesView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                cacheLimit = settingsStore.cacheLimitGB
            }
            .onChange(of: cacheLimit) { _, newValue in
                Task {
                    await settingsStore.setCacheLimit(newValue)
                }
            }
        }
    }
}

private struct ThirdPartyNoticesView: View {
    var body: some View {
        ScrollView {
            Text("""
            ONNX Runtime: MIT
            libarchive / SwiftArchive: BSD and bundled codec licenses
            UnrarKit: BSD 2-Clause plus UnRAR source license
            GRDB.swift: MIT
            TOCropViewController: MIT
            libwebp: BSD 3-Clause

            Full notices live in THIRD_PARTY_NOTICES.md in the repository.
            """)
            .font(.footnote)
            .padding()
        }
        .navigationTitle("Third-Party Notices")
    }
}
