import SwiftUI

private struct TabShortcutNumbers: EnvironmentKey {
    static let defaultValue: [UUID: Int] = [:]
}

extension EnvironmentValues {
    var tabShortcutNumbers: [UUID: Int] {
        get { self[TabShortcutNumbers.self] }
        set { self[TabShortcutNumbers.self] = newValue }
    }
}

/// An overlay leaves the tab's size, click targets and drag gestures alone.
struct TabShortcutHint: ViewModifier {
    @Environment(\.tabShortcutNumbers) private var numbers
    let tab: UUID
    var enabled = true
    var alignment: Alignment = .trailing
    var trailing: CGFloat = 2

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if enabled, let number = numbers[tab] {
                Text(String(number))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 15, height: 15)
                    .background(Palette.ground, in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.hairline) }
                    .padding(.trailing, trailing)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Command \(number)")
            }
        }
    }
}
