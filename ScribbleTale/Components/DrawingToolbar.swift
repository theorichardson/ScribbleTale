import SwiftUI
import PencilKit

struct DrawingToolbar: View {
    @Binding var selectedColor: Color
    @Binding var lineWidth: CGFloat
    @Binding var isEraser: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void

    private let colors: [Color] = [
        .black, .red, .orange, .yellow,
        .green, .blue, .purple, .brown
    ]

    var body: some View {
        VStack(spacing: 12) {
            colorPalette
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var colorPalette: some View {
        HStack(spacing: 8) {
            ForEach(colors, id: \.self) { color in
                Button {
                    selectedColor = color
                    isEraser = false
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selectedColor == color && !isEraser {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
                                    .frame(width: 38, height: 38)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                isEraser.toggle()
            } label: {
                Image(systemName: isEraser ? "eraser.fill" : "eraser")
                    .font(.title2)
                    .foregroundStyle(isEraser ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(isEraser ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            }

            Slider(value: $lineWidth, in: 2...20, step: 1)
                .tint(.secondary)

            HStack(spacing: 8) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }

                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    var currentTool: PKTool {
        if isEraser {
            return PKEraserTool(.vector)
        }
        return PKInkingTool(.pen, color: UIColor(selectedColor), width: lineWidth)
    }
}
