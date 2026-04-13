import SwiftUI
import PencilKit

struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var hasDrawn: Bool
    @Binding var canvasUndoManager: UndoManager?
    var tool: PKTool
    var backgroundColor: UIColor

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = UndoableCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.drawing = drawing
        canvas.tool = tool
        canvas.backgroundColor = backgroundColor
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        context.coordinator.applyTool(tool, to: canvas)
        DispatchQueue.main.async {
            canvasUndoManager = canvas.undoManager
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyTool(tool, to: canvas)
        if canvas.drawing.strokes.isEmpty && !drawing.strokes.isEmpty {
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        private var lastInkColor: UIColor?
        private var lastInkWidth: CGFloat?
        private var lastIsEraser = false

        init(_ parent: DrawingCanvas) {
            self.parent = parent
        }

        func applyTool(_ tool: PKTool, to canvas: PKCanvasView) {
            if let inking = tool as? PKInkingTool {
                if !lastIsEraser, inking.color == lastInkColor, inking.width == lastInkWidth {
                    return
                }
                canvas.tool = tool
                lastInkColor = inking.color
                lastInkWidth = inking.width
                lastIsEraser = false
            } else if tool is PKEraserTool {
                if lastIsEraser { return }
                canvas.tool = tool
                lastIsEraser = true
            } else {
                canvas.tool = tool
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            parent.hasDrawn = !canvasView.drawing.strokes.isEmpty
        }
    }
}

private class UndoableCanvasView: PKCanvasView {
    private let _undoManager = UndoManager()
    override var undoManager: UndoManager? { _undoManager }
}
