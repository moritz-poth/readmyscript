import AppKit
import SwiftUI

let languages: [(code: String, name: String)] = [("en", "English"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español")]

/// App-wide settings: appearance, language (English by default, not the system language), test versions.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var dark = UserDefaults.standard.object(forKey: "dark") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dark, forKey: "dark"); Log.write("setting dark \(dark)") }
    }
    @Published var betas = UserDefaults.standard.bool(forKey: "betas") {
        didSet { UserDefaults.standard.set(betas, forKey: "betas"); Log.write("setting test versions \(betas)") }
    }
    let language = UserDefaults.standard.string(forKey: "language") ?? "en"

    var theme: Theme { Theme(dark: dark) }

    /// The language is read at launch (AppleLanguages), so switching restarts the app – like MarkTheRoughcut.
    /// Not while an audiobook is being made or paused (`working`): the restart would stop it.
    func setLanguage(_ code: String) {
        guard code != language, AppModel.current?.working != true else { return }
        UserDefaults.standard.set(code, forKey: "language")
        Log.write("setting language \(code), restarting")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 $1 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                       Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        guard (try? p.run()) != nil else { return }
        NSApp.terminate(nil)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "ReadMyScriptRelease") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
