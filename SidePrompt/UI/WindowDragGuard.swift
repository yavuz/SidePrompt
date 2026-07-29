import AppKit
import SwiftUI

/// Marks a region where mouse drags must not move the NSPanel
/// (`isMovableByWindowBackground` stays enabled elsewhere).
struct WindowDragGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        GuardView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GuardView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

extension View {
    /// Prevents panel chrome dragging underneath this view.
    func disablesWindowDrag() -> some View {
        background(WindowDragGuard())
    }
}
