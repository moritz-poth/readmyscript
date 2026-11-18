import AppKit
import CryptoKit
import Foundation
import SwiftUI

// Same updater as Mountpoint (signed zips, test versions). Besides VoiceStudio on 127.0.0.1 this is the app's only
// network peer: it asks GitHub for releases and downloads the zip – no script data, nothing about the user.

/// Version from a release tag like "v1.0.0-beta.7". Final releases rank above their betas.
struct AppVersion: Comparable, Equatable {
    let numbers: [Int]
    let beta: Int?   // nil = final release

    init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") { s.removeFirst() }
        let parts = s.split(separator: "-", maxSplits: 1)
        guard let first = parts.first else { return nil }
        let nums = first.split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, !nums.contains(nil) else { return nil }
        numbers = nums.map { $0! }
        if parts.count == 2 {
            guard let b = Int(parts[1].lowercased().replacingOccurrences(of: "beta.", with: "")) else { return nil }
            beta = b
        } else {
            beta = nil
        }
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }   // 1.0 == 1.0.0

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.numbers.count, b.numbers.count)
        let x = a.numbers + Array(repeating: 0, count: n - a.numbers.count)
        let y = b.numbers + Array(repeating: 0, count: n - b.numbers.count)
        if x != y { return x.lexicographicallyPrecedes(y) }
        switch (a.beta, b.beta) {
        case let (p?, q?): return p < q
        case (_?, nil): return true
        default: return false
        }
    }
}

struct Release {
    let tag: String
    let page: URL
    let zip: URL
    /// `<zip>.sig`: Ed25519 signature of the zip (scripts/update-key.swift)
    let signature: URL?
    /// Asset `ReadMyScript-<version>.manual`: install by hand (e.g. after the update key was lost).
    let manual: Bool

    var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

    static let releasesPage = URL(string: "https://github.com/moritz-poth/readmyscript/releases")!

    /// Release page, but only on this project's GitHub – otherwise the list of releases.
    var safePage: URL { page.absoluteString.hasPrefix(Release.releasesPage.absoluteString + "/") ? page : Release.releasesPage }
}

/// Newest non-draft release with a ReadMyScript zip (and its signature), from GitHub's releases JSON.
/// Prereleases (test versions) only with `includePrereleases` – setting "Get test versions", or when a test version runs.
func newestRelease(fromJSON data: Data, requireSignature: Bool = true, includePrereleases: Bool = false) -> Release? {
    struct Asset: Decodable { let name: String; let browser_download_url: URL }
    struct R: Decodable { let tag_name: String; let html_url: URL; let draft: Bool; let prerelease: Bool?; let assets: [Asset] }
    guard let list = try? JSONDecoder().decode([R].self, from: data) else { return nil }
    return list
        .filter { !$0.draft && AppVersion($0.tag_name) != nil && (includePrereleases || $0.prerelease != true) }
        .compactMap { r -> (AppVersion, Release)? in
            guard let zip = r.assets.first(where: { $0.name.hasPrefix("ReadMyScript-") && $0.name.hasSuffix(".zip") }) else { return nil }
            let sig = r.assets.first { $0.name == zip.name + ".sig" }?.browser_download_url
            let manual = r.assets.contains { $0.name == zip.name.dropLast(4) + ".manual" }
            if requireSignature && sig == nil && !manual { return nil }
            return (AppVersion(r.tag_name)!, Release(tag: r.tag_name, page: r.html_url, zip: zip.browser_download_url, signature: sig, manual: manual))
        }
        .max { $0.0 < $1.0 }?.1
}

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate, installing
        case failed(String)
    }

    @Published var available: Release?
    @Published var state = State.idle

    static let current = AppSettings.version
    /// Public half of the update key (`swift scripts/update-key.swift public`). Only zips signed with it are installed:
    /// the codesign check alone proves the app is intact, not who made it (ad-hoc signature).
    nonisolated static let publicKey = "OWwYrEZYoqrUDPFusMIj8OB+HH3xKeYscENgvIJRpuw="
    static let api = URL(string: "https://api.github.com/repos/moritz-poth/readmyscript/releases?per_page=20")!
    /// Asks the model before installing: the restart would stop a running audiobook.
    var busy: () -> Bool = { false }
    private var timer: Timer?

    /// No cookies, no cache on disk, no proxy guesses beyond the system's.
    nonisolated static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 120
        return URLSession(configuration: c)
    }()

    /// Checks shortly after launch and then every 6 hours, quietly.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.check(manual: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(manual: false) }
        }
    }

    func check(manual: Bool) {
        guard state != .checking, state != .installing else { return }
        if manual { state = .checking }
        var request = URLRequest(url: Self.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let betas = AppSettings.shared.betas || AppVersion(Self.current)?.beta != nil
        Self.session.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap { newestRelease(fromJSON: $0, includePrereleases: betas) } : nil
            Task { @MainActor in
                guard self.state != .installing else { return }
                if let release, let new = AppVersion(release.tag), let mine = AppVersion(Self.current), mine < new {
                    if self.available?.tag != release.tag { Log.write("update available: \(release.tag)" + (release.manual ? " (install by hand)" : "")) }
                    self.available = release
                    if manual || self.state == .upToDate { self.state = .idle }
                } else if ok {
                    self.available = nil
                    if manual { self.state = .upToDate }
                } else if manual {
                    self.state = .failed(String(localized: "Could not check for updates. Check the internet connection and try again."))
                }
            }
        }.resume()
    }

    /// Downloads the zip, verifies the app inside, swaps it in place of the running app and restarts.
    func install() {
        guard let release = available, !release.manual, let sigURL = release.signature, state != .installing else { return }
        guard !busy() else { state = .failed(String(localized: "An audiobook is being made. Install the update when it is finished or cancelled.")); return }
        state = .installing
        Log.write("installing update \(release.tag)")
        Task {
            let signature = try? await Self.session.data(from: sigURL).0
            Self.session.downloadTask(with: release.zip) { file, response, error in
                if let error { Log.write("update download failed: \(error.localizedDescription)") }
                self.installDownloaded(file, response, release, signature)
            }.resume()
        }
    }

    nonisolated private func installDownloaded(_ file: URL?, _ response: URLResponse?, _ release: Release, _ signature: Data?) {
        let result: Result<URL, Error>
        if let file, (response as? HTTPURLResponse)?.statusCode == 200 {
            result = Result { try Self.unpack(file, expecting: release.tag, signature: signature) }
        } else {
            result = .failure(UpdateError(message: String(localized: "The update could not be downloaded. Check the internet connection and try again.")))
        }
        Task { @MainActor in
            switch result {
            case .success(let app):
                do { try self.swapAndRestart(with: app) } catch { self.state = .failed(error.localizedDescription) }
            case .failure(let error):
                Log.write("update failed: \(error.localizedDescription)")
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    /// The zip was signed with the update key (before anything in it is unpacked or run).
    nonisolated static func signatureValid(_ zip: Data, _ signature: Data?, publicKey: String = Updater.publicKey) -> Bool {
        guard let signature, let sig = Data(base64Encoded: String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
              let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { return false }
        return key.isValidSignature(sig, for: zip)
    }

    /// Unzips into a temporary folder and checks that it really is the expected, intact version of this app.
    nonisolated static func unpack(_ zip: URL, expecting tag: String, signature: Data?, publicKey: String = Updater.publicKey,
                                   bundleID: String? = Bundle.main.bundleIdentifier) throws -> URL {
        let damaged = UpdateError(message: String(localized: "The downloaded update is damaged. Please try again later or download it from GitHub."))
        guard let data = try? Data(contentsOf: zip, options: .mappedIfSafe), signatureValid(data, signature, publicKey: publicKey) else { throw damaged }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readmyscript-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) == 0 else { throw damaged }
        let app = dir.appendingPathComponent("Read my Script.app")
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == bundleID,
              let release = info["ReadMyScriptRelease"] as? String,
              AppVersion(release) == AppVersion(tag),
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0
        else { throw damaged }
        return app
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func swapAndRestart(with app: URL) throws {
        guard !busy() else { throw UpdateError(message: String(localized: "An audiobook is being made. Install the update when it is finished or cancelled.")) }
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        var trashed: NSURL?
        func cannotReplace(_ error: Error) -> Error {
            UpdateError(message: String(localized: "Read my Script could not replace itself. Move it to the Applications folder, or download the update from GitHub.") + "\n\n" + String(localized: "Details: \(error.localizedDescription)"))
        }
        do { try fm.trashItem(at: current, resultingItemURL: &trashed) } catch { throw cannotReplace(error) }
        do {
            try fm.moveItem(at: app, to: current)
        } catch {
            if let trashed = trashed as URL? { try? fm.moveItem(at: trashed, to: current) }
            throw cannotReplace(error)
        }
        // start the new version once this one has quit
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 $1 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                       current.path, String(ProcessInfo.processInfo.processIdentifier)]
        do { try p.run() } catch {
            state = .failed(String(localized: "The update is installed. Quit Read my Script and open it again to finish."))
            return
        }
        Log.write("update in place, restarting")
        NSApp.terminate(nil)
    }
}

/// Notice at the top of the main window when a new version is out.
struct UpdateBanner: View {
    @ObservedObject var updater = Updater.shared
    let theme: Theme
    @State private var hidden = false

    var body: some View {
        if let release = updater.available, !hidden || updater.state == .installing {
            let t = theme
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 12)).foregroundColor(t.online)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read my Script \(release.version) is available.").font(.mono(11, semibold: true)).foregroundColor(t.text)
                    if case .failed(let message) = updater.state {
                        Text(message).font(.mono(11)).foregroundColor(t.warning).fixedSize(horizontal: false, vertical: true)
                    } else if release.manual {
                        Text("This update has to be installed by hand.").font(.mono(11)).foregroundColor(t.muted)
                    } else {
                        Text("Installing restarts Read my Script.").font(.mono(11)).foregroundColor(t.muted)
                    }
                }
                Spacer(minLength: 0)
                if updater.state == .installing {
                    ProgressView().controlSize(.small)
                    Text("Installing update…").font(.mono(11)).foregroundColor(t.muted)
                } else {
                    Button("What’s new") { NSWorkspace.shared.open(release.safePage) }.buttonStyle(FerryButtonStyle(theme: t))
                    if !release.manual {
                        Button("Install update") { updater.install() }.buttonStyle(FerryButtonStyle(theme: t, primary: true))
                    }
                    Button { hidden = true } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundColor(t.muted)
                            .frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text("Close")).accessibilityLabel(Text("Close"))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(t.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
        }
    }
}
