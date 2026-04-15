import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoryFlowCoordinator.self) private var coordinator
    let config: ProviderConfig

    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false

    var body: some View {
        NavigationStack {
            Form {
                imageProviderSection
                generationStrategySection
                openAISection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
            .onAppear {
                apiKeyInput = config.openAIKey
            }
        }
    }

    // MARK: - Image Provider

    private var imageProviderSection: some View {
        Section {
            ForEach(ImageProviderType.allCases) { provider in
                Button {
                    config.imageProvider = provider
                } label: {
                    HStack {
                        Image(systemName: provider.icon)
                            .frame(width: 24)
                            .foregroundStyle(.purple)
                        Text(provider.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if config.imageProvider == provider {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.purple)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        } header: {
            Text("Image Generation")
        } footer: {
            Text("Image Playground runs on-device. OpenAI requires an API key and uses gpt-image-1.")
        }
    }

    // MARK: - Generation Strategy

    private var generationStrategySection: some View {
        Section {
            ForEach(GenerationStrategy.allCases) { strategy in
                Button {
                    config.generationStrategy = strategy
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(strategy.displayName)
                                .foregroundStyle(.primary)
                            Text(strategy.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if config.generationStrategy == strategy {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.purple)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        } header: {
            Text("Story Generation")
        } footer: {
            Text("Upfront generates the full story plan in one call (best with cloud models). Incremental builds the story beat by beat.")
        }
    }

    // MARK: - OpenAI Configuration

    private var openAISection: some View {
        Section {
            HStack {
                if showAPIKey {
                    TextField("sk-...", text: $apiKeyInput)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("sk-...", text: $apiKeyInput)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Button {
                    showAPIKey.toggle()
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .onChange(of: apiKeyInput) { _, newValue in
                config.openAIKey = newValue
            }

            if config.hasOpenAIKey {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("API key saved")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        apiKeyInput = ""
                        config.openAIKey = ""
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.red)
                }
            }
        } header: {
            Text("OpenAI API Key")
        } footer: {
            Text("Required when using GPT-4o mini or OpenAI image generation. Your key is stored in the Keychain.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Text (Local)") {
                Text(coordinator.storyEngine.loadedModel?.displayName ?? "Not loaded")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Text (Cloud)") {
                Text("GPT-4o mini")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Images (Local)") {
                Text("Image Playground")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Images (Cloud)") {
                Text("gpt-image-1")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Available Models")
        }
    }
}
