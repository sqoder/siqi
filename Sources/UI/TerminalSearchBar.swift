import AppKit
import SwiftUI

public struct TerminalSearchBar: View {
    @ObservedObject var model: SiqiWindowModel
    @State private var query: String = ""

    public init(model: SiqiWindowModel) {
        self.model = model
    }

    private var matchCounterText: String? {
        guard !query.isEmpty, let total = model.activeSession?.searchTotal else { return nil }
        if total == 0 {
            return "0/0"
        }
        if let selected = model.activeSession?.searchSelected {
            return "\(selected + 1)/\(total)"
        }
        return "\(total)"
    }

    public var body: some View {
        HStack(spacing: 6) {
            SearchFieldRepresentable(
                text: $query,
                onCommit: {
                    _ = model.activeSession?.terminalView.navigateSearch(forward: true)
                },
                onReverseCommit: {
                    _ = model.activeSession?.terminalView.navigateSearch(forward: false)
                },
                onCancel: {
                    model.endSearch()
                }
            )
            .frame(width: 180, height: 22)
            .onChange(of: query) { _, newQuery in
                _ = model.activeSession?.terminalView.search(newQuery)
            }

            if let counter = matchCounterText {
                Text(counter)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .padding(.trailing, 2)
            }

            Button {
                _ = model.activeSession?.terminalView.navigateSearch(forward: false)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Previous Match (⇧Enter / ⌘⇧G)")

            Button {
                _ = model.activeSession?.terminalView.navigateSearch(forward: true)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Next Match (Enter / ⌘G)")

            Button {
                model.endSearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Close Search (Esc)")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .onAppear {
            _ = model.activeSession?.terminalView.startSearch()
        }
    }
}

struct SearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onReverseCommit: () -> Void = {}
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search scrollback..."
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.isBordered = false
        field.backgroundColor = .clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchFieldRepresentable

        init(_ parent: SearchFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let isShift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                if isShift {
                    parent.onReverseCommit()
                } else {
                    parent.onCommit()
                }
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
