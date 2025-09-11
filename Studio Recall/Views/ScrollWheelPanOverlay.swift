#if os(macOS)
import AppKit

struct ScrollWheelPanOverlay: NSViewRepresentable {
    let onScroll: (CGSize) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = ScrollCatcher()
        v.onScroll = onScroll
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class ScrollCatcher: NSView {
        var onScroll: ((CGSize)->Void)?
        override func scrollWheel(with event: NSEvent) {
            // Natural scrolling: macOS already applies user setting; just pass deltas through
            onScroll?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
        }
    }
}
#endif
