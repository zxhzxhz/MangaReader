import SwiftUI

struct ModelProfilesView: View {
    @EnvironmentObject private var profileStore: OnnxProfileStore

    @State private var pendingModelURL: URL?
    @State private var showTemplatePicker = false

    var body: some View {
        List {
            Section("Model Files") {
                if profileStore.availableModels.isEmpty {
                    Text("Put .onnx files in Documents/Models")
                        .foregroundStyle(.secondary)
                }
                ForEach(profileStore.availableModels, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        pendingModelURL = url
                        showTemplatePicker = true
                    }
                }
            }

            Section("Profiles") {
                if profileStore.profiles.isEmpty {
                    Text("No profiles yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(profileStore.profiles) { profile in
                    NavigationLink {
                        ModelProfileEditorView(profile: profile)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                            Text("\(profile.scale)x · \(profile.modelFileName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let profile = profileStore.profiles[safe: index] {
                            try? profileStore.delete(profile)
                        }
                    }
                }
            }
        }
        .navigationTitle("ONNX Models")
        .refreshable {
            profileStore.reload()
        }
        .confirmationDialog(
            "Create Profile",
            isPresented: $showTemplatePicker,
            titleVisibility: .visible,
            presenting: pendingModelURL
        ) { url in
            ForEach(ModelProfile.builtInTemplates) { template in
                Button(template.name) {
                    try? profileStore.createFromTemplate(template, modelURL: url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("Choose a starting template for \(url.lastPathComponent).")
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
