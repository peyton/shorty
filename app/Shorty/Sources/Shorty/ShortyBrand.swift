import AppKit
import ShortyCore
import SwiftUI

enum ShortyBrand {
    static let ink = Color(red: 0.067, green: 0.09, blue: 0.086)
    static let graphite = Color(red: 0.11, green: 0.145, blue: 0.133)
    static let graphiteSoft = Color(red: 0.149, green: 0.192, blue: 0.176)
    static let mist = Color(red: 0.929, green: 0.957, blue: 0.941)
    static let teal = Color(red: 0.059, green: 0.463, blue: 0.431)
    static let amber = Color(red: 0.757, green: 0.518, blue: 0.153)
    static let muted = Color.secondary
    static let panel = Color(nsColor: .controlBackgroundColor)

    static func statusColor(for status: EngineStatus) -> Color {
        switch status {
        case .running:
            return teal
        case .disabled, .starting:
            return Color.secondary
        case .permissionRequired, .failed:
            return amber
        case .stopped:
            return Color.secondary.opacity(0.75)
        }
    }
}

struct ShortyMarkView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ShortyBrand.graphiteSoft, ShortyBrand.ink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .frame(width: size * 0.69, height: size * 0.47)
                .offset(y: size * 0.03)

            keyRows
                .frame(width: size * 0.55, height: size * 0.24)
                .offset(y: -size * 0.01)

            routePath
                .stroke(
                    ShortyBrand.teal,
                    style: StrokeStyle(
                        lineWidth: max(2, size * 0.045),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
                .fill(ShortyBrand.amber)
                .frame(width: size * 0.17, height: size * 0.045)
                .offset(x: -size * 0.22, y: size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var keyRows: some View {
        VStack(spacing: size * 0.035) {
            HStack(spacing: size * 0.035) {
                keycap()
                keycap()
                keycap()
                keycap(ShortyBrand.teal)
            }
            HStack(spacing: size * 0.035) {
                keycap()
                keycap(width: size * 0.19)
                keycap()
            }
        }
    }

    private func keycap(
        _ color: Color = ShortyBrand.ink,
        width: CGFloat? = nil
    ) -> some View {
        RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
            .fill(color)
            .frame(width: width ?? size * 0.085, height: size * 0.07)
    }

    private var routePath: Path {
        Path { path in
            path.move(to: CGPoint(x: size * 0.43, y: size * 0.66))
            path.addLine(to: CGPoint(x: size * 0.61, y: size * 0.66))
            path.addCurve(
                to: CGPoint(x: size * 0.71, y: size * 0.54),
                control1: CGPoint(x: size * 0.68, y: size * 0.66),
                control2: CGPoint(x: size * 0.71, y: size * 0.62)
            )
            path.addLine(to: CGPoint(x: size * 0.71, y: size * 0.49))
        }
    }
}

struct ShortyMenuBarGlyph: View {
    let status: EngineStatus

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.primary.opacity(0.82), lineWidth: 1.5)
                .frame(width: 17, height: 13)

            HStack(spacing: 2) {
                key
                key
                key
            }
            .offset(y: -1.5)

            Path { path in
                path.move(to: CGPoint(x: 5, y: 12))
                path.addLine(to: CGPoint(x: 11, y: 12))
                path.addCurve(
                    to: CGPoint(x: 14, y: 8),
                    control1: CGPoint(x: 13, y: 12),
                    control2: CGPoint(x: 14, y: 10)
                )
            }
            .stroke(
                ShortyBrand.statusColor(for: status),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(status.title)
    }

    private var key: some View {
        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
            .fill(Color.primary.opacity(0.82))
            .frame(width: 3.5, height: 3)
    }
}

struct ShortyStatusDot: View {
    let status: EngineStatus

    var body: some View {
        Circle()
            .fill(ShortyBrand.statusColor(for: status))
            .frame(width: 9, height: 9)
            .accessibilityLabel(status.title)
    }
}

struct ShortyPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(ShortyBrand.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            }
    }
}

struct ShortcutKeyBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                ShortyBrand.teal.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ShortyBrand.teal.opacity(0.18), lineWidth: 1)
            }
    }
}
