import SwiftUI

struct TypewriterText: View {
    let fullText: String
    var speed: TimeInterval = 0.03

    @State private var displayedText = ""
    @State private var currentIndex = 0

    var body: some View {
        Text(displayedText)
            .onChange(of: fullText) {
                displayedText = fullText
                currentIndex = fullText.count
            }
            .onAppear {
                displayedText = fullText
                currentIndex = fullText.count
            }
    }
}

struct StreamingText: View {
    let text: String
    var font: Font = .system(.title3, design: .serif)
    var color: Color = .primary

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .animation(.easeIn(duration: 0.1), value: text.count)
    }
}
