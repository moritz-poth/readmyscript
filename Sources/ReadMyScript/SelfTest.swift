import Foundation
import ScriptCore
import SwiftUI

/// Checks the app's own functions on invented test scripts – never on the user's scripts – and sends nothing anywhere:
/// the result stays on screen (and as a summary in the log).
@MainActor
final class SelfTest: ObservableObject {
    static let shared = SelfTest()

    enum Status { case pass, fail, skip }
    struct Result: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let status: Status
        let detail: String
    }
    enum Phase { case idle, running, done }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var results: [Result] = []

    func reset() { if phase != .running { phase = .idle; results = [] } }

    func start() {
        guard phase != .running else { return }
        phase = .running
        results = []
        Log.write("self-test started")
        Task {
            await run()
            let failed = results.filter { $0.status == .fail }.count
            Log.write("self-test done: \(results.count) checks, \(failed) failed")
            phase = .done
        }
    }

    private func add(_ title: LocalizedStringKey, _ status: Status, _ detail: String = "") {
        results.append(Result(title: title, status: status, detail: detail))
    }

    private func run() async {
        // 1. reading screenplays: two layouts with watermark, header, scene numbers – written to a temp folder
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rms-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var scripts: [Script] = []
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for url in DemoScript.write(to: dir) { scripts.append(try ScriptParser.parse(url)) }
            let ok = scripts.allSatisfy { $0.sceneCount == DemoScript.scenes && $0.roles.map(\.name).sorted() == DemoScript.roles }
            add("Read screenplay PDFs", ok ? .pass : .fail,
                ok ? String(localized: "Two layouts with watermark and page header recognised.") : String(localized: "The test scripts were not recognised correctly."))
        } catch {
            add("Read screenplay PDFs", .fail, error.localizedDescription)
        }

        // 2. cast and render plan: one voice per part, every line has a voice
        if let s = scripts.first {
            let cast = Cast.suggest(for: s, voices: ["n", "a", "b"])
            let plan = RenderPlan.make(s, cast: cast, language: "English")
            let voices = Set(plan.chapters.flatMap { $0.spans.map(\.voice_id) })
            let ok = plan.chapters.count == DemoScript.scenes && voices == ["n", "a", "b"] && cast.unassigned(in: s).isEmpty
            add("Plan the audiobook", ok ? .pass : .fail, String(localized: "\(plan.chapters.count) chapters, \(plan.spanCount) passages."))
        }

        // 3. VoiceStudio on this Mac
        let studio = VoiceStudio()
        guard await studio.isRunning() else {
            add("VoiceStudio is running", .fail, String(localized: "Start VoiceStudio and run the self-test again."))
            for t: LocalizedStringKey in ["Voices", "Speak a test sentence", "VoiceStudio sends nothing"] { add(t, .skip) }
            return
        }
        add("VoiceStudio is running", .pass, "127.0.0.1:3900")

        var voices: [VoiceStudio.Voice] = []
        do { voices = try await studio.voices() } catch {}
        add("Voices", voices.isEmpty ? .fail : .pass,
            voices.isEmpty ? String(localized: "VoiceStudio has no voices yet. Create some in VoiceStudio first.") : String(localized: "\(voices.count) voices"))

        if let v = voices.first {
            do {
                let wav = try await studio.preview("This is a test.", voice: v.id, language: "English")
                add("Speak a test sentence", wav.count > 1000 ? .pass : .fail, String(localized: "\(wav.count / 1024) KB audio"))
            } catch {
                add("Speak a test sentence", .fail, error.localizedDescription)
            }
        } else {
            add("Speak a test sentence", .skip)
        }

        // 4. nothing leaves the Mac through VoiceStudio
        let analytics = VoiceStudio.analyticsEnabled() == true
        let sync = await studio.cloudSyncOn()
        add("VoiceStudio sends nothing", analytics || sync ? .fail : .pass,
            analytics ? String(localized: "VoiceStudio's usage statistics are on – switch them off in VoiceStudio.")
            : sync ? String(localized: "VoiceStudio's cloud sync is on – switch it off in VoiceStudio.")
            : String(localized: "Usage statistics and cloud sync are off."))
    }
}

/// Settings → Support → self-test: start, progress, result. Nothing is sent.
struct SelfTestView: View {
    let theme: Theme
    @ObservedObject var test: SelfTest
    let done: () -> Void

    var body: some View {
        let t = theme
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: String(localized: "Self-test"), theme: t)
            if test.phase == .idle {
                Text("Read my Script tests reading screenplays, planning the audiobook and VoiceStudio with invented test scripts. Your scripts are not touched and nothing is sent. It takes about half a minute.")
                    .font(.mono(12)).foregroundColor(t.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                list(t)
            }
            if test.phase == .done {
                let fail = test.results.filter { $0.status == .fail }.count
                let pass = test.results.filter { $0.status == .pass }.count, skip = test.results.filter { $0.status == .skip }.count
                Text("\(pass) passed, \(fail) failed, \(skip) skipped")
                    .font(.mono(12, semibold: true)).foregroundColor(fail > 0 ? t.warning : t.text)
            }
            Rectangle().fill(t.line).frame(height: 1)
            HStack(spacing: 10) {
                Button("Back", action: done).buttonStyle(FerryButtonStyle(theme: t)).disabled(test.phase == .running)
                Spacer()
                switch test.phase {
                case .idle: Button("Start self-test") { test.start() }.buttonStyle(FerryButtonStyle(theme: t, primary: true)).keyboardShortcut(.defaultAction)
                case .running: ProgressView().controlSize(.small)
                case .done: Button("Run again") { test.start() }.buttonStyle(FerryButtonStyle(theme: t))
                }
            }
        }
    }

    private func list(_ t: Theme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(test.results) { r in
                    HStack(alignment: .top, spacing: 8) {
                        // shape and colour: filled check, filled cross, empty minus
                        Image(systemName: r.status == .pass ? "checkmark.circle.fill" : r.status == .fail ? "xmark.circle.fill" : "minus.circle")
                            .resizable().frame(width: 12, height: 12).padding(.top, 2)
                            .foregroundColor(r.status == .pass ? t.online : r.status == .fail ? t.warning : t.faint)
                            .accessibilityLabel(r.status == .pass ? Text("Passed") : r.status == .fail ? Text("Failed") : Text("Skipped"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.mono(12)).foregroundColor(t.text)
                            if !r.detail.isEmpty {
                                Text(verbatim: r.detail).font(.mono(10)).foregroundColor(r.status == .fail ? t.warning : t.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if test.phase == .running {
                    HStack(spacing: 8) { ProgressView().controlSize(.mini).frame(width: 12); Text("Testing…").font(.mono(12)).foregroundColor(t.muted) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(height: 190)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(t.line, lineWidth: 1))
    }
}
