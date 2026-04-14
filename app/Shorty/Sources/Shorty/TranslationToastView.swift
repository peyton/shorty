import ShortyCore
import SwiftUI

/// A transient toast notification shown when a shortcut is translated (#1, #21).
/// Auto-dismisses after a brief interval. Shows translation successes during
/// the learning phase, and failures always.
struct TranslationToastView: View {
    let event: TranslationEvent
    let onDismiss: () -> Void

    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.canonicalName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(event.inputKeys.displayString) → \(event.actionDescription)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(event.appName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .frame(maxWidth: 380)
        .opacity(opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shorty translated \(event.canonicalName) for \(event.appName)")
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                opacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onDismiss()
                }
            }
        }
    }

    private var iconName: String {
        if event.succeeded == false {
            return "exclamationmark.triangle.fill"
        }
        return "keyboard.fill"
    }

    private var iconColor: Color {
        if event.succeeded == false {
            return ShortyBrand.amber
        }
        return ShortyBrand.teal
    }

    private var borderColor: Color {
        if event.succeeded == false {
            return ShortyBrand.amber
        }
        return ShortyBrand.teal
    }
}

/// Manages the toast display queue. Shown as an overlay on the app's menu bar extra.
final class ToastManager: ObservableObject {
    @Published var currentToast: TranslationEvent?

    private var queue: [TranslationEvent] = []
    private var isShowing = false

    func enqueue(_ event: TranslationEvent) {
        queue.append(event)
        showNextIfIdle()
    }

    func dismiss() {
        isShowing = false
        currentToast = nil
        showNextIfIdle()
    }

    private func showNextIfIdle() {
        guard !isShowing, let next = queue.first else { return }
        queue.removeFirst()
        isShowing = true
        currentToast = next
    }
}
