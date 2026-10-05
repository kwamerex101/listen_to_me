import SwiftUI

/// Holds the single pending "Undo" action for a view. Starting a new one
/// drops the older action without running it, and the toast dismisses
/// itself after `lifetime` seconds.
@MainActor
final class UndoCenter: ObservableObject {
    struct Pending: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
    }

    @Published private(set) var pending: Pending?

    private let lifetime: Duration = .seconds(5)
    private var timer: Task<Void, Never>?

    func show(_ message: String, undo: @escaping () -> Void) {
        let item = Pending(message: message, undo: undo)
        pending = item
        timer?.cancel()
        timer = Task { [weak self, lifetime] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            if self?.pending?.id == item.id { self?.pending = nil }
        }
    }

    func performUndo() {
        guard let item = pending else { return }
        dismiss()
        item.undo()
    }

    func dismiss() {
        timer?.cancel()
        timer = nil
        pending = nil
    }
}

/// Compact capsule card with a message and an Undo button.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: DT.space4) {
            Text(message)
                .font(DT.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button(action: onUndo) {
                Text("Undo")
                    .font(DT.captionStrong)
                    .foregroundStyle(DT.accent)
            }
            .buttonStyle(.pressable)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo (⌘Z)")
            .accessibilityLabel("Undo")
        }
        .padding(.horizontal, DT.space4)
        .padding(.vertical, DT.space2)
        .background(
            Capsule().fill(.regularMaterial)
        )
        .overlay(
            Capsule().strokeBorder(DT.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Overlays the center's pending toast at the bottom, centred.
    func undoToast(_ center: UndoCenter) -> some View {
        modifier(UndoToastModifier(center: center))
    }
}

private struct UndoToastModifier: ViewModifier {
    @ObservedObject var center: UndoCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let item = center.pending {
                    UndoToast(message: item.message, onUndo: { center.performUndo() })
                        .padding(.bottom, DT.space6)
                        .id(item.id)
                        .transition(reduceMotion
                                    ? .opacity
                                    : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : Motion.selection, value: center.pending?.id)
    }
}
