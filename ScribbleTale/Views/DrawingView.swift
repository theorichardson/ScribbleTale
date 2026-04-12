import SwiftUI
import PencilKit

struct DrawingView: View {
    let chapterIndex: Int

    @Environment(StoryFlowCoordinator.self) private var coordinator
    @State private var hasDrawn = false
    @State private var selectedColor: Color = .black
    @State private var lineWidth: CGFloat = 5
    @State private var isEraser = false
    @State private var undoManager: UndoManager?

    private var chapter: Chapter? {
        coordinator.story?.chapters[safe: chapterIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            promptBanner
            canvas
            toolbar
            letsGoButton
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Chapter \(chapterIndex + 1) of 5")
                    .font(.system(.headline, design: .rounded))
            }
        }
    }

    private var promptBanner: some View {
        Text(chapter?.drawingPrompt ?? "Draw something!")
            .font(.system(.title2, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                (coordinator.story?.storyType.color ?? .purple).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 0)
            )
    }

    private var canvas: some View {
        GeometryReader { geo in
            let tool: PKTool = isEraser
                ? PKEraserTool(.vector)
                : PKInkingTool(.pen, color: UIColor(selectedColor), width: lineWidth)

            DrawingCanvas(
                drawing: Binding(
                    get: { chapter?.drawing ?? PKDrawing() },
                    set: { chapter?.drawing = $0 }
                ),
                hasDrawn: $hasDrawn,
                tool: tool,
                backgroundColor: .white
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
                chapter?.drawing = PKDrawing()
                hasDrawn = false
            }
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var letsGoButton: some View {
        Button {
            coordinator.goToImageReveal(chapterIndex: chapterIndex)
        } label: {
            Text("Let's Go!")
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

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
