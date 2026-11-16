import AppKit
import SwiftUI

/// Native AppKit window drag area for moving the window and double-click zoom/restore.
public final class WindowDragHandleView: NSView {
    public override var mouseDownCanMoveWindow: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if let window, window.frame.width <= 100 && window.frame.height <= 36,
               let wc = window.windowController as? TerminalWindowController {
                wc.restoreFromCapsule()
                return
            }
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
            if action == "Minimize" {
                window?.miniaturize(nil)
                return
            } else if action != "None" {
                window?.zoom(nil)
                return
            }
        }
        window?.performDrag(with: event)
    }
}

public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> WindowDragHandleView {
        let view = WindowDragHandleView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    public func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}
