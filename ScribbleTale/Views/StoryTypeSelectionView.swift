import os
import SwiftUI

private let log = Logger(subsystem: "com.scribbletale.app", category: "StoryTypeSelection")

struct StoryTypeSelectionView: View {
    @Environment(StoryFlowCoordinator.self) private var coordinator
    @AppStorage("selectedModel") private var selectedModelRaw = StoryModel.gemma3_1B.rawValue
    @State private var isModelLoading = false
    @State private var showSettings = false

    private var selectedModel: StoryModel {
        StoryModel(rawValue: selectedModelRaw) ?? .gemma3_1B
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                modelPicker
                genreGrid
                if isModelLoading {
                    loadingIndicator
                } else {
                    availabilitySummary
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.purple.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.purple)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(config: coordinator.config)
        }
        .task {
            log.info("task: starting model load + availability checks")
            isModelLoading = true

            coordinator.selectTextModel(selectedModel)
            log.info("task: loading LLM — \(selectedModel.displayName)")
            await coordinator.storyEngine.loadModel(selectedModel)
            log.info("task: LLM load finished — isLoaded=\(coordinator.storyEngine.isLoaded)")

            log.info("task: checking image provider availability...")
            coordinator.refreshImageProvider()
            await coordinator.imageService.checkAvailability()
            log.info("task: image check done — available=\(coordinator.imageService.isAvailable)")

            isModelLoading = false
            log.info("task: all loading complete")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("ScribbleTale")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .pink, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Pick your story!")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Model Picker

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Story Model")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(StoryModel.allCases) { model in
                        ModelCard(
                            model: model,
                            isSelected: model == selectedModel,
                            isLoading: isModelLoading && model == selectedModel
                        ) {
                            selectModel(model)
                        }
                        .disabled(isModelLoading)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
    }

    private func selectModel(_ model: StoryModel) {
        guard model != selectedModel else { return }
        selectedModelRaw = model.rawValue
        coordinator.selectTextModel(model)
        Task {
            isModelLoading = true
            await coordinator.storyEngine.loadModel(model)
            isModelLoading = false
        }
    }

    // MARK: - Genre Grid

    private var genreGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(StoryType.allCases) { type in
                StoryTypeCard(storyType: type) {
                    coordinator.startStory(type: type)
                }
                .disabled(isModelLoading || !coordinator.storyEngine.isLoaded)
                .opacity(isModelLoading || !coordinator.storyEngine.isLoaded ? 0.6 : 1.0)
            }
        }
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView(value: coordinator.storyEngine.loadingProgress)
                .tint(.purple)

            Text(coordinator.storyEngine.loadingStatus.isEmpty
                 ? "Preparing..."
                 : coordinator.storyEngine.loadingStatus)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.2), value: coordinator.storyEngine.loadingStatus)

            if coordinator.storyEngine.loadingProgress > 0 && coordinator.storyEngine.loadingProgress < 1.0 {
                Text("First time may take a moment to download (\(selectedModel.downloadSize))")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else if coordinator.storyEngine.isLoaded && !coordinator.imageService.isAvailable {
                Text("Checking Image Playground...")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
    }

    // MARK: - Availability Summary

    private var availabilitySummary: some View {
        VStack(spacing: 6) {
            availabilityLine(
                title: "Story Engine (\(selectedModel.displayName))",
                available: coordinator.storyEngine.isLoaded
            )
            availabilityLine(
                title: coordinator.config.imageProvider.displayName,
                available: coordinator.imageService.isAvailable
            )
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func availabilityLine(title: String, available: Bool) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .orange)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
            Spacer()
            Text(available ? "Ready" : "Unavailable")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Model Card

private struct ModelCard: View {
    let model: StoryModel
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: model.icon)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .purple)

                    Text(model.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(isSelected ? .white : .primary)

                    Spacer()

                    if isSelected && isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .font(.system(.subheadline))
                    }
                }

                Text(model.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)

                Text(model.downloadSize)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
            }
            .padding(12)
            .frame(width: 170)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(
                              colors: [.purple, .purple.opacity(0.8)],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing))
                          : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
