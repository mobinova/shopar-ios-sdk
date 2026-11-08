import SwiftUI

/// Public appearance tokens for the Agency SDK's bundled SwiftUI screens.
/// Colors are ARGB values so hosts can construct a style without depending on Shopar assets.
public struct AgencyStyle: Sendable, Equatable {
    public let backgroundColor: UInt32
    public let surfaceColor: UInt32
    public let surfaceSubtleColor: UInt32
    public let textColor: UInt32
    public let secondaryTextColor: UInt32
    public let borderColor: UInt32
    public let primaryColor: UInt32
    public let onPrimaryColor: UInt32
    public let accentColor: UInt32
    public let onAccentColor: UInt32
    public let dangerColor: UInt32
    public let cardCornerRadius: Double
    public let controlCornerRadius: Double
    public let isDark: Bool

    public init(
        backgroundColor: UInt32 = 0xFFF6F7F2,
        surfaceColor: UInt32 = 0xFFFFFFFF,
        surfaceSubtleColor: UInt32 = 0xFFEFF2E9,
        textColor: UInt32 = 0xFF18221D,
        secondaryTextColor: UInt32 = 0xFF59655D,
        borderColor: UInt32 = 0xFFDDE3D8,
        primaryColor: UInt32 = 0xFF18221D,
        onPrimaryColor: UInt32 = 0xFFFFFFFF,
        accentColor: UInt32 = 0xFFD8F36A,
        onAccentColor: UInt32 = 0xFF18221D,
        dangerColor: UInt32 = 0xFFAD2F3E,
        cardCornerRadius: Double = 14,
        controlCornerRadius: Double = 10,
        isDark: Bool = false
    ) {
        self.backgroundColor = backgroundColor
        self.surfaceColor = surfaceColor
        self.surfaceSubtleColor = surfaceSubtleColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.borderColor = borderColor
        self.primaryColor = primaryColor
        self.onPrimaryColor = onPrimaryColor
        self.accentColor = accentColor
        self.onAccentColor = onAccentColor
        self.dangerColor = dangerColor
        self.cardCornerRadius = min(max(cardCornerRadius, 0), 32)
        self.controlCornerRadius = min(max(controlCornerRadius, 0), 32)
        self.isDark = isDark
    }

    public static let shopar = AgencyStyle()
    public static let midnight = AgencyStyle(
        backgroundColor: 0xFF101714, surfaceColor: 0xFF1A231E, surfaceSubtleColor: 0xFF26312B,
        textColor: 0xFFF6F7F2, secondaryTextColor: 0xFFBBC7BE, borderColor: 0xFF47554C,
        primaryColor: 0xFFD8F36A, onPrimaryColor: 0xFF18221D,
        accentColor: 0xFFD8F36A, onAccentColor: 0xFF18221D,
        dangerColor: 0xFFFFB4AB, cardCornerRadius: 18, controlCornerRadius: 12, isDark: true
    )
}

extension UInt32 {
    var shoparAgencyColor: Color {
        Color(.sRGB, red: Double((self >> 16) & 0xFF) / 255,
              green: Double((self >> 8) & 0xFF) / 255,
              blue: Double(self & 0xFF) / 255,
              opacity: Double((self >> 24) & 0xFF) / 255)
    }
}

struct ShoparAgencyPrimaryButtonStyle: ButtonStyle {
    let style: AgencyStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(style.onAccentColor.shoparAgencyColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? style.accentColor.shoparAgencyColor.opacity(0.82) : style.accentColor.shoparAgencyColor,
                        in: RoundedRectangle(cornerRadius: style.controlCornerRadius))
    }
}
