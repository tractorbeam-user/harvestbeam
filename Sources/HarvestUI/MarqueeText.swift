import SwiftUI

/// One line of text that truncates normally, and while `isActive` (hover)
/// slides across to show the part that didn't fit, fading at the edges.
/// Text that fits never moves.
struct MarqueeText: View {
    let text: String
    var isActive: Bool

    @State private var fullWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isRunning = false

    private static let fade: CGFloat = 14
    /// Points per second; slow enough to read.
    private static let speed: CGFloat = 32

    private var overflow: CGFloat { max(0, fullWidth - boxWidth) }
    private var scrolls: Bool { isActive && overflow > 1 }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(isRunning ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { boxWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in boxWidth = width }
                }
            )
            // The whole line, measured at its natural width.
            .background(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { fullWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, width in fullWidth = width }
                        }
                    )
            }
            .overlay(alignment: .leading) {
                if isRunning {
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: offset)
                        // A fixed width: a flexible frame would grow to the
                        // full line and the clip would let it spill out.
                        .frame(width: boxWidth, alignment: .leading)
                        .clipped()
                        .mask(edgeFades)
                        .accessibilityHidden(true)
                }
            }
            .task(id: scrolls) { await run() }
    }

    /// Fades the trailing edge, and the leading one once the text has moved.
    /// The glide goes one fade further than the overflow, so the last letter
    /// comes to rest clear of the trailing fade.
    private var edgeFades: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().opacity(offset < -0.5 ? 0 : 1)
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
            }
            .frame(width: Self.fade)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
        }
    }

    /// Glide to the end, rest, glide back, rest, for as long as it's hovered.
    private func run() async {
        guard scrolls else {
            if isRunning {
                withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                try? await Task.sleep(for: .milliseconds(200))
                isRunning = false
            }
            return
        }
        // A short beat first, so passing over a tile doesn't set it off.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isRunning = true
        while !Task.isCancelled {
            let distance = overflow + Self.fade
            let duration = Double(distance / Self.speed)
            withAnimation(.easeInOut(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration + 1.1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: duration * 0.6)) { offset = 0 }
            try? await Task.sleep(for: .seconds(duration * 0.6 + 1.1))
        }
    }
}
