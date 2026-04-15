import SwiftUI
import PencilKit

struct DrawingView: View {
    let chapterIndex: Int

    private let sectionSpacing: CGFloat = 14

    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var hasDrawn = false
    @State private var selectedColor: Color = .black
    @State private var lineWidth: CGFloat = 5
    @State private var isEraser = false
    @State private var undoManager: UndoManager?

    private var state: NarrativeState? {
        coordinator.story?.narrativeState
    }

    private var challenge: DrawingChallenge? {
        state?.pendingChallenge
    }

    var body: some View {
        VStack(spacing: 0) {
            chapterProgressBar
            VStack(spacing: sectionSpacing) {
                promptBanner
                canvas
                toolbar
                letsGoButton
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Beat \(chapterIndex + 1) of \(coordinator.story?.chapterCount ?? 5)")
                    .font(.system(.headline, design: .rounded))
            }
        }
    }

    private var chapterProgressBar: some View {
        HStack(spacing: 6) {
            let totalBeats = coordinator.story?.chapterCount ?? 5
            ForEach(0..<totalBeats, id: \.self) { i in
                Capsule()
                    .fill(
                        i < chapterIndex
                            ? (coordinator.story?.storyType.color ?? .purple)
                            : i == chapterIndex
                                ? (coordinator.story?.storyType.color ?? .purple).opacity(0.5)
                                : Color(.systemGray4)
                    )
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var promptBanner: some View {
        Text(challenge?.drawingPrompt ?? "Draw something!")
            .font(.system(.title2, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let tool: PKTool = isEraser
                ? PKEraserTool(.vector)
                : PKInkingTool(.pen, color: UIColor(selectedColor), width: lineWidth)

            DrawingCanvas(
                drawing: Binding(
                    get: { state?.drawing(for: chapterIndex) ?? PKDrawing() },
                    set: { newDrawing in
                        state?.setDrawing(newDrawing, for: chapterIndex)
                    }
                ),
                hasDrawn: $hasDrawn,
                canvasUndoManager: $undoManager,
                tool: tool,
                backgroundColor: .white
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .padding(.horizontal, 16)
        }
    }

    private var toolbar: some View {
        DrawingToolbar(
            selectedColor: $selectedColor,
            lineWidth: $lineWidth,
            isEraser: $isEraser,
            onUndo: {
                undoManager?.undo()
            },
            onRedo: {
                undoManager?.redo()
            },
            onClear: {
                state?.setDrawing(PKDrawing(), for: chapterIndex)
                hasDrawn = false
            }
        )
        .padding(.horizontal, 12)
    }

    private var letsGoButton: some View {
        Button {
            coordinator.goToImageReveal(chapterIndex: chapterIndex)
        } label: {
            Text("Let's go!")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    hasDrawn
                        ? (coordinator.story?.storyType.color ?? .purple)
                        : Color.gray.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 20)
                )
        }
        .disabled(!hasDrawn)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.3), value: hasDrawn)
    }
}
