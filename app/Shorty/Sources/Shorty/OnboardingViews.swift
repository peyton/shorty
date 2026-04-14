import ShortyCore
import SwiftUI

// MARK: - Interactive demo (#3)

/// "Try it now" exercise shown after Accessibility permission is granted.
struct TryItNowExercise: View {
    @State private var showResult = false

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Try it now")
                        .font(.callout.weight(.semibold))
                } icon: {
                    Image(systemName: "hand.tap")
                        .foregroundColor(ShortyBrand.teal)
                }

                Text("Switch to any supported app and press a keyboard shortcut. Shorty will translate it automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Try these:")
                            .font(.caption.weight(.semibold))
                        ExerciseRow(keys: "⌘L", name: "Focus URL Bar", app: "in any browser")
                        ExerciseRow(keys: "⌘⇧P", name: "Command Palette", app: "in VS Code")
                        ExerciseRow(keys: "⌃Tab", name: "Next Tab", app: "in any tabbed app")
                    }
                    Spacer()
                }
            }
        }
    }
}

private struct ExerciseRow: View {
    let keys: String
    let name: String
    let app: String

    var body: some View {
        HStack(spacing: 6) {
            ShortcutKeyBadge(text: keys)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.caption.weight(.medium))
                Text(app)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Persona quick start (#4)

/// Quick-start presets for different user personas.
struct PersonaQuickStart: View {
    let onSelectPersona: (Persona) -> Void

    enum Persona: String, CaseIterable {
        case developer = "Developer"
        case webWorker = "Web & Productivity"
        case universal = "Universal"

        var icon: String {
            switch self {
            case .developer: return "chevron.left.forwardslash.chevron.right"
            case .webWorker: return "globe"
            case .universal: return "keyboard"
            }
        }

        var description: String {
            switch self {
            case .developer:
                return "I switch between code editors, terminals, and browsers."
            case .webWorker:
                return "I use Google Workspace, Slack, and Notion in the browser."
            case .universal:
                return "I want consistent shortcuts in every app."
            }
        }

        var highlightedCategories: [CanonicalShortcut.Category] {
            switch self {
            case .developer:
                return [.navigation, .search, .tabs, .editing]
            case .webWorker:
                return [.navigation, .tabs, .editing]
            case .universal:
                return CanonicalShortcut.Category.allCases
            }
        }
    }

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("How do you use your Mac?")
                    .font(.callout.weight(.semibold))
                Text("This helps Shorty highlight the shortcuts you'll use most.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(Persona.allCases, id: \.self) { persona in
                    Button {
                        onSelectPersona(persona)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: persona.icon)
                                .foregroundColor(ShortyBrand.teal)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(persona.rawValue)
                                    .font(.callout.weight(.medium))
                                Text(persona.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(persona.rawValue): \(persona.description)")
                }
            }
        }
    }
}

// MARK: - Welcome walkthrough (#5)

/// A 3-step popover overlay explaining key concepts.
struct WelcomeWalkthrough: View {
    @State private var step = 0
    let onDismiss: () -> Void

    private let steps: [(title: String, detail: String, icon: String)] = [
        (
            "Status at a glance",
            "The header shows whether Shorty is active and which app is in front. The badge shows how many shortcuts are available.",
            "circle.grid.2x2"
        ),
        (
            "Your shortcuts",
            "This list shows every shortcut Shorty can translate for the current app. 'Sends keys' means a key remap; 'Menu' means Shorty clicks the menu item for you.",
            "keyboard"
        ),
        (
            "Translation toggle",
            "The switch controls whether Shorty is actively translating shortcuts. You can also pause for just the current app or for a set time.",
            "switch.2"
        )
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Welcome to Shorty")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if step < steps.count {
                let current = steps[step]
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: current.icon)
                        .foregroundColor(ShortyBrand.teal)
                        .font(.title3)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.title)
                            .font(.caption.weight(.semibold))
                        Text(current.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Text("Step \(step + 1) of \(steps.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if step > 0 {
                    Button("Back") {
                        step -= 1
                    }
                    .controlSize(.small)
                }
                if step < steps.count - 1 {
                    Button("Next") {
                        step += 1
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Got it") {
                        onDismiss()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome walkthrough, step \(step + 1) of \(steps.count)")
    }
}
