import AppKit
import AVFoundation
import NaturalLanguage
import ScriptCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case rendering(done: Int, total: Int, assembling: Bool)
        case paused(done: Int, total: Int)
        case finished(URL, failed: Int)
        case failed(String)
    }

    @Published var pdf: URL?
    @Published var script: Script?
    @Published var openError: String?
    @Published var studioReady = false
    @Published var analyticsOn = false
    @Published var cloudSyncOn = false
    @Published var studioInstalled = StudioSetup.installedURL != nil
    /// VoiceStudio's speech model is downloaded (nil = VoiceStudio not running, unknown)
    @Published var modelsReady: Bool?
    /// The window shows the VoiceStudio setup instead of the app until this is false.
    var needsSetup: Bool { !studioInstalled || (studioReady && modelsReady == false) }
    private var madePrivate = false
    @Published var voices: [VoiceStudio.Voice] = []
    @Published var cast = Cast()
    /// "German", "English" or nil (VoiceStudio decides per voice)
    @Published var language: String?
    @Published var phase = Phase.idle
    @Published var previewing: String?     // role being previewed ("" = narrator)

    private let studio = VoiceStudio()
    private var renderTask: Task<Void, Never>?
    private var renderGeneration = 0
    private var job: String?
    private var target: URL?
    private var player: AVAudioPlayer?
    private var poll: Timer?

    var busy: Bool { if case .rendering = phase { return true }; return false }
    /// Rendering or paused: a restart (language, update) would lose the audiobook in progress.
    var working: Bool { switch phase { case .rendering, .paused: return true; default: return false } }
    /// The one window's model, for the settings (language switch and update wait while an audiobook is made).
    static weak var current: AppModel?

    init() { Self.current = self }

    func start() {
        Task { await refreshStudio() }
        poll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshStudio() }
        }
    }

    func refreshStudio() async {
        studioInstalled = StudioSetup.installedURL != nil
        analyticsOn = VoiceStudio.analyticsEnabled() == true
        let ready = await studio.isRunning()
        cloudSyncOn = ready ? await studio.cloudSyncOn() : false
        modelsReady = ready ? await studio.modelsReady() : nil
        // while VoiceStudio is being set up for Read my Script: switch off what sends data, once per launch
        if ready, !madePrivate, StudioSetup.shared.state == .done || modelsReady == false {
            madePrivate = true
            await makeStudioPrivate()
        }
        if ready && (!studioReady || voices.isEmpty) {
            do {
                voices = try await studio.voices()
                Log.write("VoiceStudio ready, \(voices.count) voices")
                if script != nil && cast.narrator == nil { suggestCast() }
            } catch { Log.write("voices failed: \(error.localizedDescription)") }
        }
        studioReady = ready
    }

    func launchStudio() {
        guard let app = StudioSetup.installedURL else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }

    /// Usage statistics, cloud sync and network sharing off in VoiceStudio.
    func makeStudioPrivate() async {
        let ok = await studio.makePrivate()
        Log.write("VoiceStudio privacy settings switched off" + (ok ? "" : " (VoiceStudio refused one)"))
        analyticsOn = VoiceStudio.analyticsEnabled() == true
        cloudSyncOn = await studio.cloudSyncOn()
    }

    // MARK: - Script

    func open(_ url: URL) {
        guard !busy, !needsSetup else { return }
        do {
            let s = try ScriptParser.parse(url)
            pdf = url; script = s; openError = nil; phase = .idle
            language = Self.detectLanguage(s.spokenSample)
            cast = Cast()
            suggestCast()
            Log.write("opened \(url.lastPathComponent): \(s.sceneCount) scenes, \(s.roles.count) roles, \(s.elements.count) paragraphs")
        } catch {
            openError = error.localizedDescription
            Log.write("open failed \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func close() {
        guard !busy else { return }
        pdf = nil; script = nil; phase = .idle; openError = nil
    }

    private func suggestCast() {
        guard let script, !voices.isEmpty else { return }
        cast = Cast.suggest(for: script, voices: voices.map(\.id))
    }

    static func detectLanguage(_ text: String) -> String? {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.german, .english]
        r.processString(text)
        switch r.dominantLanguage {
        case .german: return "German"
        case .english: return "English"
        default: return nil
        }
    }

    func voiceName(_ id: String?) -> String? { id.flatMap { id in voices.first { $0.id == id }?.name } }

    func setOverride(_ id: Int, _ o: Cast.Override?) { cast.overrides[id] = o }

    // MARK: - Listen

    /// Plays a line of this role (nil = narrator) in its current voice.
    func preview(role: String?) {
        guard let voice = role.map({ cast.roles[$0] ?? nil }) ?? cast.narrator else { return }
        play(role) { [studio, language] in try await studio.preview($0, voice: voice, language: language) }
    }

    /// Plays a line of this role in a voice that is not saved yet.
    func preview(role: String?, design: VoiceDesign) {
        play(role) { [studio, language] in try await studio.preview($0, design: design, language: language) }
    }

    private func play(_ role: String?, _ make: @escaping @Sendable (String) async throws -> Data) {
        guard let script else { return }
        let line = script.elements.first { role == nil ? $0.kind == .action : $0.kind == .dialogue && $0.role == role }
        guard let text = line?.text else { return }
        player?.stop()
        previewing = role ?? ""
        let sample = String(text.prefix(220))
        Task {
            defer { previewing = nil }
            do {
                player = try AVAudioPlayer(data: try await make(sample))
                player?.play()
            } catch {
                Log.write("preview failed: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    /// Saves the designed voice in VoiceStudio and gives it to the role (nil = narrator).
    func createVoice(_ design: VoiceDesign, name: String, for role: String?) async -> Bool {
        do {
            let id = try await studio.create(design, name: name, language: language)
            voices = try await studio.voices()
            if let role { cast.roles[role] = .some(id) } else { cast.narrator = id }
            Log.write("voice created: \(design.instruct), seed \(design.seed)")
            return true
        } catch {
            Log.write("create voice failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Render

    var plan: RenderPlan? { script.map { RenderPlan.make($0, cast: cast, language: language) } }

    func create(to url: URL) {
        target = url
        render()
    }

    private func render() {
        guard let plan, let target, plan.spanCount > 0 else { return }
        Log.write("render start: \(plan.chapters.count) chapters, \(plan.spanCount) spans → \(target.path)")
        phase = .rendering(done: 0, total: plan.chapters.count, assembling: false)
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        renderTask = Task {
            // an older render (before pause/resume) must not touch the state of the new one
            var current: Bool { generation == renderGeneration && !Task.isCancelled }
            do {
                for try await ev in studio.render(plan) {
                    guard current, case .rendering(let done, let total, _) = phase else { break }
                    switch ev {
                    case .started(let n, let id): job = id; phase = .rendering(done: 0, total: n, assembling: false)
                    case .chapterDone(let i, let n): phase = .rendering(done: max(done, i + 1), total: n, assembling: false)
                    case .chapterFailed(let i): Log.write("chapter \(i + 1) failed")
                    case .assembling: phase = .rendering(done: total, total: total, assembling: true)
                    case .progress: break
                    case .stopped: break
                    case .done(let output, let failed):
                        try await studio.collect(output, to: target)
                        Log.write("render done: \(target.path), failed chapters \(failed.count)")
                        phase = .finished(target, failed: failed.count)
                    }
                }
                if current, case .rendering = phase { phase = .failed(String(localized: "VoiceStudio stopped without a result.")) }
            } catch is CancellationError {
            } catch {
                if !current { return }
                Log.write("render failed: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops VoiceStudio; finished scenes stay in its cache, so Resume continues where it stopped.
    func pause() {
        guard case .rendering(let done, let total, _) = phase else { return }
        phase = .paused(done: done, total: total)
        renderTask?.cancel()
        Log.write("render paused at \(done)/\(total)")
    }

    func resume() {
        guard case .paused = phase else { return }
        render()
    }

    func cancel() {
        renderTask?.cancel()
        phase = .idle
        if let job { VoiceStudio.removeWorkFolder(job: job); self.job = nil }
        Log.write("render cancelled")
    }

    func suggestedFileName() -> String {
        (script?.title ?? "Script").replacingOccurrences(of: "/", with: "-") + ".m4b"
    }
}

/// ~/Library/Logs/ReadMyScript/ReadMyScript.log – events only, never script text.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ReadMyScript/ReadMyScript.log")
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()

    static func reveal() { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    static func write(_ s: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? fm.removeItem(at: old); try? fm.moveItem(at: url, to: old)
        }
        let line = Data("\(fmt.string(from: Date())) \(s)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: url) }
    }
}
