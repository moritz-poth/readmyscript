import AppKit
import CoreText
import SwiftUI

@main
struct ReadMyScriptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    init() {
        // English unless the user picked another language in Settings (read before the first text is loaded)
        UserDefaults.standard.set([UserDefaults.standard.string(forKey: "language") ?? "en"], forKey: "AppleLanguages")
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "fonts") ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        Window("Read my Script", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 600)
                .onAppear {
                    delegate.model = model
                    Log.write("start \(AppSettings.version) \(arch)")
                    model.start()
                    Updater.shared.busy = { [weak model] in model?.working == true }
                    Updater.shared.start()
                }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Read my Script") { SettingsWindow.shared.show(.about) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") { openPanel(model) }.keyboardShortcut("o").disabled(model.busy || model.needsSetup)
            }
            CommandGroup(replacing: .help) {
                Button("Read my Script Manual") { openWindow(id: "manual") }.keyboardShortcut("?")
                Button("Show Log File") { Log.reveal() }
            }
        }

        Window("Read my Script Manual", id: "manual") { ManualView() }
            .defaultSize(width: 640, height: 720)
    }

    private var arch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

/// Opening PDFs from the Finder ("Open With", drag onto the Dock icon).
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel? {
        didSet { if let model, let url = pending { pending = nil; model.open(url) } }
    }
    @MainActor private var pending: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated { if let model { model.open(url) } else { pending = url } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
