import AppKit
import CryptoKit
import ScriptCore
import Security
import SwiftUI

/// Installs VoiceStudio from its official GitHub releases, only after three checks: the zip's SHA-256 from the
/// release's checksum list, Apple's code signature by VoiceStudio's team (`StudioRelease.teamID`) and Apple's
/// notarisation. Nothing about the user or a script is sent – only the download itself.
@MainActor
final class StudioSetup: ObservableObject {
    static let shared = StudioSetup()

    enum State: Equatable {
        case idle
        case downloading(Double)   // 0…1
        case checking
        case failed(String)
        case done
    }

    @Published private(set) var state = State.idle

    /// VoiceStudio's app bundle, wherever LaunchServices knows it (not a copy in the Trash).
    static var installedURL: URL? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: StudioRelease.bundleID),
              !url.path.contains("/.Trash/"), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var busy: Bool { switch state { case .downloading, .checking: return true; default: return false } }

    private nonisolated static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()

    func install() {
        guard !busy, Self.installedURL == nil else { return }
        state = .downloading(0)
        Log.write("VoiceStudio install started")
        Task {
            do {
                let app = try await download()
                state = .checking
                let target = try await Task.detached { try Self.verifyAndMove(app) }.value
                Log.write("VoiceStudio installed at \(target.path)")
                state = .done
                NSWorkspace.shared.openApplication(at: target, configuration: .init(), completionHandler: nil)
            } catch {
                Log.write("VoiceStudio install failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func fail(_ s: String.LocalizationValue) -> UpdateError { UpdateError(message: String(localized: s)) }

    /// Release info → checksum list → zip (streamed to a temp file with progress) → SHA-256 → unzipped app.
    private func download() async throws -> URL {
        var request = URLRequest(url: StudioRelease.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let noNet = Self.fail("VoiceStudio could not be downloaded. Check the internet connection and try again.")
        guard let (json, resp) = try? await Self.session.data(for: request), (resp as? HTTPURLResponse)?.statusCode == 200 else { throw noNet }
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x64"
        #endif
        guard let asset = StudioRelease.asset(fromJSON: json, arch: arch) else {
            throw Self.fail("No VoiceStudio download for this Mac was found. Use the download page instead.")
        }
        guard let (sums, r2) = try? await Self.session.data(from: asset.checksums), (r2 as? HTTPURLResponse)?.statusCode == 200,
              let expected = StudioRelease.checksum(for: asset.zipName, in: String(decoding: sums, as: UTF8.self)) else { throw noNet }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rms-voicestudio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent(asset.zipName)
        FileManager.default.createFile(atPath: zip.path, contents: nil)
        let out = try FileHandle(forWritingTo: zip)
        var hash = SHA256()
        do {
            let (bytes, r3) = try await Self.session.bytes(from: asset.zip)
            guard (r3 as? HTTPURLResponse)?.statusCode == 200 else { throw noNet }
            let total = Double(max(r3.expectedContentLength, 1))
            var buffer = Data(); buffer.reserveCapacity(1 << 20)
            var written = 0.0, shown = 0.0
            for try await b in bytes {
                buffer.append(b)
                if buffer.count >= 1 << 20 {
                    out.write(buffer); hash.update(data: buffer); written += Double(buffer.count); buffer.removeAll(keepingCapacity: true)
                    if written / total - shown > 0.01 { shown = written / total; state = .downloading(min(shown, 1)) }
                }
            }
            out.write(buffer); hash.update(data: buffer)
            try out.close()
        } catch {
            try? out.close()
            throw noNet
        }
        let got = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard got == expected else { throw Self.fail("The VoiceStudio download is damaged. Please try again.") }

        guard Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) == 0 else {
            throw Self.fail("The VoiceStudio download is damaged. Please try again.")
        }
        return dir.appendingPathComponent("VoiceStudio.app")
    }

    /// Signed by VoiceStudio's team, intact, notarised by Apple – then moved to /Applications (or ~/Applications).
    nonisolated static func verifyAndMove(_ app: URL) throws -> URL {
        let wrong = fail("This VoiceStudio download is not signed by its developer. It was not installed.")
        guard Bundle(url: app)?.bundleIdentifier == StudioRelease.bundleID else { throw wrong }
        // one check for "intact" + "Developer ID of exactly this team"
        var code: SecStaticCode?
        var req: SecRequirement?
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(StudioRelease.teamID)\"" as CFString
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement, [], &req) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), req) == errSecSuccess
        else { throw wrong }
        // Gatekeeper: notarised Developer ID (same check macOS makes on first launch of a downloaded app)
        guard run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]) == 0 else { throw wrong }

        let fm = FileManager.default
        let system = URL(fileURLWithPath: "/Applications/VoiceStudio.app")
        let user = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/VoiceStudio.app")
        for target in [system, user] {
            if fm.fileExists(atPath: target.path) { continue }   // never replace something that is already there
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: app, to: target)) != nil {
                try? fm.removeItem(at: app.deletingLastPathComponent())
                return target
            }
        }
        throw fail("VoiceStudio could not be put into the Applications folder. Use the download page instead.")
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
}

/// Shown instead of the drop zone until VoiceStudio is installed and has its speech model.
struct StudioSetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var setup = StudioSetup.shared
    let theme: Theme

    var body: some View {
        let t = theme
        VStack(alignment: .leading, spacing: 16) {
            Text("Read my Script needs VoiceStudio").font(.mono(15, semibold: true))
            Text("VoiceStudio is a free app that speaks the voices – on this Mac, without the internet. Read my Script sends it the script and gets the audiobook back.")
                .foregroundColor(t.muted).fixedSize(horizontal: false, vertical: true)

            step(done: model.studioInstalled, Text("Install VoiceStudio")) {
                if !model.studioInstalled { installControls(t) }
            }
            step(done: model.studioInstalled && model.studioReady, Text("Start VoiceStudio")) {
                if model.studioInstalled && !model.studioReady {
                    Button("Start VoiceStudio") { model.launchStudio() }.buttonStyle(FerryButtonStyle(theme: t, primary: true))
                }
            }
            step(done: model.modelsReady == true, Text("Download the speech model in VoiceStudio")) {
                if model.studioReady && model.modelsReady != true {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VoiceStudio's own setup downloads its speech model (about 2.4 GB) and shows its license – it is for non-commercial use. Please read and accept it there yourself.")
                            .font(.mono(11)).foregroundColor(t.faint).fixedSize(horizontal: false, vertical: true)
                        Button("Show VoiceStudio") { model.launchStudio() }.buttonStyle(FerryButtonStyle(theme: t, primary: true))
                    }
                }
            }
            step(done: model.studioReady && !model.analyticsOn && !model.cloudSyncOn, Text("Keep everything on this Mac")) {
                if model.studioReady {
                    Text("Read my Script switches off VoiceStudio's usage statistics, cloud sync and network sharing.")
                        .font(.mono(11)).foregroundColor(t.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.mono(12))
        .foregroundColor(t.text)
        .frame(maxWidth: 560, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func installControls(_ t: Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch setup.state {
            case .downloading(let p):
                HStack(spacing: 10) {
                    ProgressView(value: p).frame(width: 220)
                    (Text("Downloading VoiceStudio…") + Text(verbatim: " \(Int(p * 100)) %")).foregroundColor(t.muted).monospacedDigit()
                }
            case .checking:
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Checking the signature…").foregroundColor(t.muted) }
            default:
                HStack(spacing: 10) {
                    Button("Install VoiceStudio") { setup.install() }.buttonStyle(FerryButtonStyle(theme: t, primary: true))
                    Button("Download page") { NSWorkspace.shared.open(StudioRelease.page) }.buttonStyle(FerryButtonStyle(theme: t))
                }
                if case .failed(let message) = setup.state {
                    Text(message).foregroundColor(t.warning).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Downloads the current version from VoiceStudio's official GitHub page and installs it in the Applications folder – only if Apple confirms it is signed by its developer and unchanged.")
                .font(.mono(11)).foregroundColor(t.faint).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One line of the checklist: filled check when done, empty ring when not (shape, not only colour).
    private func step<C: View>(done: Bool, _ title: Text, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? theme.online : theme.faint).font(.system(size: 14)).padding(.top, 1)
                .accessibilityLabel(done ? Text("Done") : Text("To do"))
            VStack(alignment: .leading, spacing: 8) {
                title.font(.mono(13, semibold: true)).foregroundColor(done ? theme.muted : theme.text)
                content()
            }
        }
    }
}
