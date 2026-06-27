import SwiftUI

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48
    static let massive: CGFloat = 64
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 9999
}

// MARK: - Fonts

extension Font {
    static let orbitBody = Font.system(.body, design: .default)
    static let orbitBodySmall = Font.system(.subheadline, design: .default)
    static let orbitCaption = Font.system(.caption, design: .default)
    static let orbitCaptionSmall = Font.system(.caption2, design: .default)
    static let orbitHeadline = Font.system(.headline, design: .default)
    static let orbitSubheadline = Font.system(.subheadline, design: .default)
    static let orbitTitle = Font.system(.title, design: .default)
    static let orbitTitle2 = Font.system(.title2, design: .default)
    static let orbitTitle3 = Font.system(.title3, design: .default)
    static let orbitMono = Font.system(.body, design: .monospaced)
    static let orbitMonoSmall = Font.system(.caption, design: .monospaced)
}

// MARK: - Colors

// Orbit brand palette — see TARGET DESIGN spec
extension Color {
    static let orbitPrimary = Color(red: 0.902, green: 0.929, blue: 0.969)       // #E6EDF7
    static let orbitSecondary = Color(red: 0.545, green: 0.584, blue: 0.592)     // #8B95A7
    static let orbitTertiary = Color(red: 0.545, green: 0.584, blue: 0.592).opacity(0.6)

    static let orbitBackground = Color(red: 0.043, green: 0.058, blue: 0.090)    // #0B0F17
    static let orbitSurface = Color(red: 0.071, green: 0.094, blue: 0.149)       // #121826
    static let orbitSurfaceSecondary = Color(red: 0.102, green: 0.133, blue: 0.196) // #1A2232
    static let orbitBorder = Color.white.opacity(0.06)
    static let orbitAccent = Color(red: 0.302, green: 0.639, blue: 1.0)          // #4DA3FF
    static let orbitAccentDim = Color(red: 0.302, green: 0.639, blue: 1.0).opacity(0.12)
    static let orbitSuccess = Color(red: 0.180, green: 0.898, blue: 0.578)       // #2EE59D
    static let orbitWarning = Color(red: 1.0, green: 0.800, blue: 0.400)         // #FFCC66
    static let orbitError = Color(red: 1.0, green: 0.361, blue: 0.361)           // #FF5C5C
    static let orbitInfo = Color(red: 0.302, green: 0.639, blue: 1.0)

    // Timeline / execution colours
    static let orbitTimelineLine = Color.white.opacity(0.08)
    static let orbitSurfaceHover = Color(red: 0.302, green: 0.639, blue: 1.0).opacity(0.05)
    static let orbitGlowBlue = Color(red: 0.302, green: 0.639, blue: 1.0).opacity(0.15)
}



// MARK: - ShapeStyle Conformance

extension ShapeStyle where Self == Color {
    static var orbitPrimary: Color { .orbitPrimary }
    static var orbitSecondary: Color { .orbitSecondary }
    static var orbitTertiary: Color { .orbitTertiary }
    static var orbitBackground: Color { .orbitBackground }
    static var orbitSurface: Color { .orbitSurface }
    static var orbitSurfaceSecondary: Color { .orbitSurfaceSecondary }
    static var orbitBorder: Color { .orbitBorder }
    static var orbitAccent: Color { .orbitAccent }
    static var orbitAccentDim: Color { .orbitAccentDim }
    static var orbitSuccess: Color { .orbitSuccess }
    static var orbitWarning: Color { .orbitWarning }
    static var orbitError: Color { .orbitError }
    static var orbitInfo: Color { .orbitInfo }
    static var orbitTimelineLine: Color { .orbitTimelineLine }
    static var orbitSurfaceHover: Color { .orbitSurfaceHover }
    static var orbitGlowBlue: Color { .orbitGlowBlue }
}

// MARK: - Shadow

extension View {
    func orbitShadow(_ radius: CGFloat = 12, y: CGFloat = 4) -> some View {
        shadow(color: .black.opacity(0.08), radius: radius, x: 0, y: y)
    }
}

// MARK: - Card Style

struct OrbitCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
            .orbitShadow()
    }
}

extension View {
    func orbitCard() -> some View {
        modifier(OrbitCardStyle())
    }
}

// MARK: - Chip Style

struct OrbitChipStyle: ViewModifier {
    var color: Color = .orbitAccentDim

    func body(content: Content) -> some View {
        content
            .font(.orbitCaptionSmall)
            .foregroundStyle(.orbitSecondary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }
}

extension View {
    func orbitChip(color: Color = .orbitAccentDim) -> some View {
        modifier(OrbitChipStyle(color: color))
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let color: Color
    let isAnimating: Bool

    init(_ color: Color = .orbitSuccess, animating: Bool = false) {
        self.color = color
        self.isAnimating = animating
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                isAnimating
                    ? Circle().stroke(color.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.5)
                        .opacity(isAnimating ? 0.3 : 0)
                    : nil
            )
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .textCase(.uppercase)
            if let count {
                Text("\(count)")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xxs)
    }
}

// MARK: - Loading State

struct OrbitLoadingState: View {
    var message: String = "Loading..."

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.orbitCaption)
                .foregroundStyle(.orbitSecondary)
        }
    }
}

// MARK: - Empty State

struct OrbitEmptyState: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.orbitTertiary)
            Text(title)
                .font(.orbitTitle3)
                .foregroundStyle(.orbitPrimary)
            Text(description)
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 200)
    }
}
