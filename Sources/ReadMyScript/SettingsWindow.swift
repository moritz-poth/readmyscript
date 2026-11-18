import AppKit
import SwiftUI

/// Settings in their own window like Mountpoint's: toolbar tabs (icon over name), 800 × 450, never grows,
/// last tab restored. "About Read my Script" opens the same window on the About tab.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    enum Pane: Int, CaseIterable {
        case general, updates, support, about
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .updates: return "arrow.triangle.2.circlepath"
            case .support: return "lifepreserver"
            case .about: return "info.circle"
            }
        }
        var title: String {
            switch self {
            case .general: return String(localized: "General")
            case .updates: return String(localized: "Updates")
            case .support: return String(localized: "Support")
            case .about: return String(localized: "About")
            }
        }
    }

    static let size = NSSize(width: 800, height: 450)   // 16:9, whole window
    private var window: NSWindow?
    private var tabs: SettingsTabs?

    /// `nil` = the last tab used other than About (Settings… ⌘,)
    func show(_ pane: Pane? = nil) {
        if window == nil { build() }
        let last = Pane(rawValue: UserDefaults.standard.integer(forKey: "settingsPane")) ?? .general
        tabs?.selectedTabViewItemIndex = (pane ?? (last == .about ? .general : last)).rawValue
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        for pane in Pane.allCases {
            let host = NSHostingController(rootView: SettingsPane(pane: pane))
            host.sizingOptions = []
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable]   // minimize and zoom dimmed
        w.toolbar?.allowsUserCustomization = false
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setFrame(NSRect(origin: .zero, size: Self.size), display: false)
        w.center()
        window = w
        self.tabs = tabs
    }
}

/// Remembers the tab and keeps the window at 16:9 whatever a tab contains.
final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: "settingsPane")
        if let w = view.window, w.frame.size != SettingsWindow.size {
            w.setFrame(NSRect(origin: w.frame.origin, size: SettingsWindow.size), display: true)
        }
    }
}

/// One tab: Ferry look, centred column of 560, never scrolls (only the self-test list does).
struct SettingsPane: View {
    let pane: SettingsWindow.Pane
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var test = SelfTest.shared
    @State private var selfTest = false

    var body: some View {
        let t = settings.theme
        VStack(alignment: .leading, spacing: 14) { content(t) }
            .font(.mono())
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(t.background)
            .environment(\.colorScheme, settings.dark ? .dark : .light)
    }

    /// Explanation below a row, wrapping before the column of switches and buttons.
    private func hint(_ text: LocalizedStringKey, _ t: Theme) -> some View {
        Text(text).font(.mono(11)).foregroundColor(t.faint).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 390, alignment: .leading)
    }

    private func row<C: View>(_ text: Text, _ t: Theme, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 10) {
            text.foregroundColor(t.text)
            Spacer()
            control()
        }
    }

    @ViewBuilder private func content(_ t: Theme) -> some View {
        switch pane {
        case .general:
            SwitchRow(title: "Light/Dark", on: settings.dark, theme: t) { settings.dark.toggle() }
            hint("Switches every window between a light and a dark look.", t)
            row(Text("Language"), t) {
                Dropdown(title: Text(verbatim: languages.first { $0.code == settings.language }?.name ?? "English"), theme: t) {
                    ForEach(languages, id: \.code) { l in
                        Button(l.name) { settings.setLanguage(l.code) }.disabled(l.code == settings.language)
                    }
                }
                .disabled(AppModel.current?.working == true)
            }
            hint("Changing the language restarts Read my Script. Not possible while an audiobook is being made.", t)

        case .updates:
            row(Text("Version \(Updater.current)"), t) {
                if updater.state == .checking { ProgressView().controlSize(.small) }
                Button("Check for updates") { updater.check(manual: true) }
                    .buttonStyle(FerryButtonStyle(theme: t))
                    .disabled(updater.state == .checking || updater.state == .installing)
            }
            switch updater.state {
            case .upToDate:
                Text("Read my Script is up to date.").font(.mono(11)).foregroundColor(t.faint)
            case .failed(let message) where updater.available == nil:
                Text(message).font(.mono(11)).foregroundColor(t.warning).fixedSize(horizontal: false, vertical: true)
            default:
                if let r = updater.available {
                    Text("Read my Script \(r.version) is available.").font(.mono(11)).foregroundColor(t.text)
                }
            }
            hint("Read my Script asks GitHub for new versions on its own and shows a notice. Only this question goes out – never anything from your scripts.", t)
            SwitchRow(title: "Get test versions", on: settings.betas, theme: t) { settings.betas.toggle(); updater.check(manual: false) }
            hint("Also offers versions that are still being tested. For testers only – they can contain errors.", t)

        case .support:
            if selfTest {
                SelfTestView(theme: t, test: test) { selfTest = false; test.reset() }
            } else {
                row(test.phase == .running ? Text("Self-test running…") : Text("Test this Mac"), t) {
                    Button("Run self-test…") { selfTest = true }.buttonStyle(FerryButtonStyle(theme: t))
                }
                hint("Tests reading screenplays and VoiceStudio with invented test scripts. Nothing is sent.", t)
                row(Text("Events and errors"), t) {
                    Button("Show log file") { Log.reveal() }.buttonStyle(FerryButtonStyle(theme: t))
                }
                hint("The log lists what the app did, without any text from your scripts. Send it along if you ask for help.", t)
                row(Text("Like Read my Script?"), t) {
                    Button("Buy me a coffee") { NSWorkspace.shared.open(AboutView.coffee) }.buttonStyle(FerryButtonStyle(theme: t))
                }
                hint("If you use Read my Script and like it, I would be glad if you bought me a coffee.", t)
            }

        case .about:
            AboutView(theme: t)
        }
    }
}

/// Legal notices (GPL-3.0 §5d): copyright, no warranty, license, source code, third parties.
struct AboutView: View {
    let theme: Theme

    static let repo = URL(string: "https://github.com/moritz-poth/readmyscript")!
    static let gpl = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    static let coffee = URL(string: "https://buymeacoffee.com/moritzpoth")!

    var body: some View {
        let t = theme
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Read my Script").font(.mono(15, semibold: true)).foregroundColor(t.text)
                    Text("Version \(AppSettings.version)").font(.mono(12)).foregroundColor(t.muted)
                    Text(verbatim: "© 2026 Moritz Poth").font(.mono(12)).foregroundColor(t.muted)
                }
            }
            Text("Read my Script is free software: you can redistribute and modify it under the terms of the GNU General Public License, version 3 or later.")
                .font(.mono(12)).foregroundColor(t.text).fixedSize(horizontal: false, vertical: true)
            Text("It comes with ABSOLUTELY NO WARRANTY – use at your own risk.")
                .font(.mono(12)).foregroundColor(t.text).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Source code") { NSWorkspace.shared.open(Self.repo) }.buttonStyle(FerryButtonStyle(theme: t))
                Button("License") {
                    if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) }
                    else { NSWorkspace.shared.open(Self.gpl) }
                }
                .buttonStyle(FerryButtonStyle(theme: t))
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(title: String(localized: "Third-party"), theme: t)
                Text("JetBrains Mono font – SIL Open Font License 1.1")
                Text("Needs VoiceStudio, which is not included and has its own license. Read my Script is not affiliated with VoiceStudio.")
            }
            .font(.mono(11)).foregroundColor(t.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
