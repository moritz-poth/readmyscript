import SwiftUI

/// Same typography and colours as MediaFiles Ferry, Mountpoint and MarkTheRoughcut. Dark by default, light optional.
struct Theme {
    var dark = true
    private func c(_ d: UInt32, _ l: UInt32) -> Color {
        let v = dark ? d : l
        return Color(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    var background: Color { c(0x1f2225, 0xf5f5f3) }
    var panel: Color { c(0x181a1c, 0xebebe8) }
    var text: Color { c(0xeceded, 0x17191b) }
    var muted: Color { c(0xa9adb1, 0x3f444a) }
    var faint: Color { c(0x858b91, 0x60666c) }   // dark 4.6:1 (WCAG AA)
    var line: Color { c(0x3a3f44, 0xc4c8cc) }
    var primary: Color { c(0xe6e7e8, 0x2e3236) }
    var onPrimary: Color { c(0x1f2225, 0xf5f5f3) }
    var warning: Color { c(0xf0883e, 0xb4530f) }   // light 4.6:1 – also text
    var selection: Color { c(0x24282c, 0xdfe2e5) }
    var field: Color { c(0x30353a, 0xffffff) }
    var fieldLine: Color { c(0x121416, 0xaab0b6) }
    var online: Color { c(0x3fb950, 0x1a7f37) }   // ready dot
}

extension Font {
    static func mono(_ size: CGFloat = 13, semibold: Bool = false) -> Font {
        .custom(semibold ? "JetBrainsMono-SemiBold" : "JetBrainsMono-Regular", size: size)
    }
}

struct FerryButtonStyle: ButtonStyle {
    let theme: Theme
    var primary = false
    var height: CGFloat = 26
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(12, semibold: primary))
            .foregroundColor(!enabled ? theme.faint : primary ? theme.onPrimary : theme.text)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(primary && enabled ? theme.primary.opacity(configuration.isPressed ? 0.85 : 1)
                                                             : theme.text.opacity(configuration.isPressed ? 0.12 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary && enabled ? theme.primary : theme.line, lineWidth: 1))
            .contentShape(Rectangle())
            .fixedSize()
    }
}

/// Drop-down that looks like the other buttons (own chevron, system indicator hidden) – lines up flush.
struct Dropdown<Content: View>: View {
    let title: Text
    let theme: Theme
    @ViewBuilder let content: () -> Content
    var body: some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                title
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
        }
        .menuStyle(.button)
        .buttonStyle(FerryButtonStyle(theme: theme))
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// On/off switch in the Ferry look.
struct Switch: View {
    let on: Bool
    let theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? theme.primary : theme.line)
                Circle().fill(on ? theme.onPrimary : (theme.dark ? theme.muted : theme.background)).padding(2)
            }
            .frame(width: 34, height: 20)
            .animation(.easeOut(duration: 0.15), value: on)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(Text(on ? "On" : "Off"))
    }
}

/// Section heading in small caps, like Mountpoint's.
struct SectionTitle: View {
    let title: String
    let theme: Theme
    var body: some View {
        Text(title.uppercased()).font(.mono(11, semibold: true)).tracking(1).foregroundColor(theme.muted)
            .lineLimit(1).truncationMode(.middle)
    }
}

/// Text left, switch right; the whole row toggles (Mountpoint's SwitchRow).
struct SwitchRow: View {
    let title: LocalizedStringKey
    let on: Bool
    let theme: Theme
    let action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.mono()).foregroundColor(theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Switch(on: on, theme: theme, action: action)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(on ? Text("On") : Text("Off"))
        .accessibilityAddTraits(.isButton)
    }
}
