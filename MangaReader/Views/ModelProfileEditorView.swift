import SwiftUI

struct ModelProfileEditorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profileStore: OnnxProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var profile: ModelProfile
    @State private var validationMessage: String?

    init(profile: ModelProfile) {
        _profile = State(initialValue: profile)
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $profile.name)
                Picker("Model File", selection: $profile.modelFileName) {
                    ForEach(profileStore.availableModels, id: \.self) { url in
                        Text(url.lastPathComponent).tag(url.lastPathComponent)
                    }
                }
            }

            Section("Inference") {
                Stepper("Scale: \(profile.scale)x", value: $profile.scale, in: 1...8)
                Stepper("Tile Size: \(profile.tileSize)", value: $profile.tileSize, in: 128...1024, step: 32)
                Stepper("Overlap: \(profile.overlap)", value: $profile.overlap, in: 0...64)
                TextField("Input Tensor", text: $profile.inputName)
                    .textInputAutocapitalization(.never)
                TextField("Output Tensor", text: $profile.outputName)
                    .textInputAutocapitalization(.never)
            }

            Section("Image Format") {
                Picker("Color Space", selection: $profile.colorSpace) {
                    ForEach(ProfileColorSpace.allCases, id: \.self) { value in
                        Text(value.rawValue.uppercased()).tag(value)
                    }
                }
                Picker("Normalization", selection: $profile.normalization) {
                    ForEach(ProfileNormalization.allCases, id: \.self) { value in
                        Text(value == .zeroToOne ? "0 to 1" : "0 to 255").tag(value)
                    }
                }
                Picker("Alpha Mode", selection: $profile.alphaMode) {
                    ForEach(ProfileAlphaMode.allCases, id: \.self) { value in
                        Text(value == .ignore ? "Ignore" : "Separate").tag(value)
                    }
                }
            }

            Section("Execution") {
                Picker("Provider", selection: $profile.executionProvider) {
                    ForEach(ExecutionProvider.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }

            Section("Validation") {
                Button("Run Validation") {
                    Task {
                        do {
                            let result = try await model.upscaleService.validate(profile)
                            validationMessage = "OK \(result.width)x\(result.height)"
                        } catch {
                            validationMessage = error.localizedDescription
                        }
                    }
                }
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Denoise") {
                Picker("Level", selection: Binding(
                    get: { profile.denoiseLevel ?? 0 },
                    set: { profile.denoiseLevel = $0 == 0 ? nil : $0 }
                )) {
                    Text("None").tag(0)
                    Text("Level 1").tag(1)
                    Text("Level 2").tag(2)
                    Text("Level 3").tag(3)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try profileStore.save(profile)
                        dismiss()
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
