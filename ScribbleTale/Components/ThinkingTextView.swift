import SwiftUI

struct ThinkingTextView: View {
    let text: String
    @State private var isExpanded = false

    private static let displayCap = 2000

    private var displayText: String {
        if text.count > Self.displayCap {
            return "…" + text.suffix(Self.displayCap)
        }
        return text
    }

    var body: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(.caption2))
                            .symbolEffect(.pulse, isActive: true)
                        Text("Thinking…")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.purple.opacity(0.6))
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ScrollView {
                        Text(displayText)
                            .font(.system(.caption, design: .monospaced))
                            .italic()
                            .foregroundStyle(.secondary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .padding(.horizontal, 8)
        }
    }
}
