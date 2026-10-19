import SwiftUI

/// Shared look: navy palette (see scripts/make_colors.py), rounded type,
/// soft cards, springy presses. Keep screens composed from these.
enum Design {
    static let cornerRadius: CGFloat = 22
    static let smallCornerRadius: CGFloat = 14
    static let spacing: CGFloat = 16

    /// The default spring for UI state changes.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.62)

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [.brandNavy, .brandNavyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension ActivityType {
    var tint: Color {
        switch self {
        case .gym: .gymTint
        case .run: .runTint
        case .ride: .rideTint
        }
    }
}

// MARK: - Surfaces

extension View {
    /// Content on a rounded card.
    func card(padding: CGFloat = Design.spacing) -> some View {
        self
            .padding(padding)
            .background(.cardBackground, in: .rect(cornerRadius: Design.cornerRadius, style: .continuous))
    }

    /// App background behind lists and forms, with card-colored rows.
    func appListStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
    }

    /// App background behind plain screens.
    func appBackground() -> some View {
        background(Color.appBackground.ignoresSafeArea())
    }
}

/// Row background for lists using `appListStyle()`.
extension View {
    func cardRow() -> some View {
        listRowBackground(Color.cardBackground)
    }
}

// MARK: - Buttons

/// Shrinks slightly with a spring while pressed. Use for custom tiles and cards.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Design.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// A big, filled call-to-action with a springy press.
struct ProminentStyle: ButtonStyle {
    var tint: Color = .accentColor
    var height: CGFloat = 64

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(tint.gradient, in: .capsule)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.1 : 0.3), radius: configuration.isPressed ? 4 : 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Design.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProminentStyle {
    static func prominent(_ tint: Color = .accentColor, height: CGFloat = 64) -> ProminentStyle {
        ProminentStyle(tint: tint, height: height)
    }
}

// MARK: - Small pieces

/// An SF Symbol in a tinted rounded square.
struct IconBadge: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A caption over a large rounded number, e.g. on summary cards.
struct StatView: View {
    let title: LocalizedStringKey
    let value: String
    var valueFont: Font = .system(.title2, design: .rounded, weight: .bold)
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(verbatim: value)
                .font(valueFont)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fades and lifts content in on appear, optionally after a delay (for staggering).
struct AppearEffect: ViewModifier {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(Design.spring.delay(reduceMotion ? 0 : delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func appearEffect(delay: Double = 0) -> some View {
        modifier(AppearEffect(delay: delay))
    }
}
