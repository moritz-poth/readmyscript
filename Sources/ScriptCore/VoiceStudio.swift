import Foundation

/// The local VoiceStudio server. This is the only network peer of the app: loopback only,
/// so the script never leaves the computer.
public struct VoiceStudio: Sendable {
    public static let base = URL(string: "http://127.0.0.1:3900")!
    /// VoiceStudio keeps its data (prefs, outputs) here.
    public static let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OmniVoice")

    public struct Voice: Decodable, Identifiable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var language: String?
    }

    public enum Event: Sendable, Equatable {
        case started(chapters: Int, job: String)
        case progress(chapter: Int, total: Int)
        case chapterDone(index: Int, total: Int)
        case chapterFailed(index: Int)
        case assembling
        case done(output: String, failed: [Int])
        case stopped
    }

    public struct Failure: LocalizedError {
        public var message: String
        public var errorDescription: String? { message }
    }

    let session: URLSession

    public init() {
        let c = URLSessionConfiguration.ephemeral   // nothing cached on disk
        c.timeoutIntervalForRequest = 600
        c.connectionProxyDictionary = [:]           // never through a proxy
        session = URLSession(configuration: c)
    }

    public func isRunning() async -> Bool {
        var r = URLRequest(url: Self.base.appendingPathComponent("health")); r.timeoutInterval = 2
        guard let (_, resp) = try? await session.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    public func voices() async throws -> [Voice] {
        let (data, resp) = try await session.data(from: Self.base.appendingPathComponent("profiles"))
        try check(resp, data)
        return try JSONDecoder().decode([Voice].self, from: data).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// One short line in one voice, as WAV data (for "listen").
    public func preview(_ text: String, voice: String, language: String?) async throws -> Data {
        try await post("generate", [("text", text), ("profile_id", voice), ("language", language ?? "Auto"), ("num_step", "16")])
    }

    /// One short line in a voice that is not saved yet.
    public func preview(_ text: String, design: VoiceDesign, language: String?) async throws -> Data {
        try await post("generate", [("text", text), ("instruct", design.instruct), ("seed", String(design.seed)),
                                    ("language", language ?? "Auto"), ("num_step", "16")])
    }

    /// Saves a designed voice as a VoiceStudio profile; returns its id.
    public func create(_ design: VoiceDesign, name: String, language: String?) async throws -> String {
        let data = try await post("profiles", [("name", name), ("kind", "design"), ("instruct", design.instruct),
                                               ("vd_states", design.states), ("seed", String(design.seed)),
                                               ("language", language ?? "Auto")])
        struct P: Decodable { var id: String }
        return try JSONDecoder().decode(P.self, from: data).id
    }

    private func post(_ path: String, _ fields: [(String, String)]) async throws -> Data {
        var r = URLRequest(url: Self.base.appendingPathComponent(path))
        r.httpMethod = "POST"
        let boundary = "rms-\(UUID().uuidString)"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        for (k, v) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        r.httpBody = body
        let (data, resp) = try await session.data(for: r)
        try check(resp, data)
        return data
    }

    /// Whether VoiceStudio's speech model is downloaded (its own setup does that, with the model's license). nil = unknown.
    public func modelsReady() async -> Bool? {
        struct S: Decodable { var models_ready: Bool }
        guard let (d, _) = try? await session.data(from: Self.base.appendingPathComponent("setup/status")),
              let s = try? JSONDecoder().decode(S.self, from: d) else { return nil }
        return s.models_ready
    }

    /// Switches off everything in VoiceStudio that sends data off this Mac or opens it to the network:
    /// usage statistics, cloud sync, sharing on the local network. Returns false if VoiceStudio refused one.
    @discardableResult
    public func makePrivate() async -> Bool {
        var ok = true
        func send(_ path: String, method: String, json: String? = nil) async {
            var r = URLRequest(url: Self.base.appendingPathComponent(path))
            r.httpMethod = method
            if let json { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = Data(json.utf8) }
            let code = ((try? await session.data(for: r))?.1 as? HTTPURLResponse)?.statusCode
            if code != 200 { ok = false }
        }
        await send("api/settings/analytics", method: "PUT", json: #"{"enabled":false}"#)
        if await cloudSyncOn() { await send("api/cloud-sync/off", method: "POST") }
        if await networkSharingOn() { await send("system/network/disable", method: "POST") }
        return ok
    }

    /// VoiceStudio's "share on the local network" (off by default): other devices could then use it.
    public func networkSharingOn() async -> Bool {
        struct S: Decodable { var enabled: Bool }
        guard let (d, _) = try? await session.data(from: Self.base.appendingPathComponent("system/network/state")),
              let s = try? JSONDecoder().decode(S.self, from: d) else { return false }
        return s.enabled
    }

    /// VoiceStudio's cloud sync (needs an account; off by default). When on, profiles and settings leave the Mac.
    public func cloudSyncOn() async -> Bool {
        struct S: Decodable { var enabled: Bool }
        guard let (d, _) = try? await session.data(from: Self.base.appendingPathComponent("api/cloud-sync/status")),
              let s = try? JSONDecoder().decode(S.self, from: d) else { return false }
        return s.enabled
    }

    /// Renders the plan; events arrive as VoiceStudio streams them. Cancelling the task stops the render.
    public func render(_ plan: RenderPlan) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                do {
                    var r = URLRequest(url: Self.base.appendingPathComponent("longform/render"))
                    r.httpMethod = "POST"
                    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    r.timeoutInterval = 24 * 3600
                    r.httpBody = try JSONEncoder().encode(plan)
                    let (bytes, resp) = try await session.bytes(for: r)
                    if (resp as? HTTPURLResponse)?.statusCode != 200 {
                        var d = Data(); for try await b in bytes { d.append(b) }
                        try check(resp, d)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = Data(line.dropFirst(5).utf8)
                        // keep-alives and other non-JSON lines are skipped; an "error" event still throws
                        guard (try? JSONSerialization.jsonObject(with: json)) != nil else { continue }
                        if let ev = try Self.event(json) { cont.yield(ev) }
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    static func event(_ json: Data) throws -> Event? {
        struct E: Decodable {
            var type: String
            var index: Int?, total: Int?, chapters: Int?
            var output: String?, error: String?, job_id: String?
            var failed_chapters: [Int]?
        }
        let e = try JSONDecoder().decode(E.self, from: json)
        switch e.type {
        case "started": return .started(chapters: e.chapters ?? 0, job: e.job_id ?? "")
        case "progress": return .progress(chapter: e.index ?? 0, total: e.total ?? 0)
        case "chapter": return .chapterDone(index: e.index ?? 0, total: e.total ?? 0)
        case "chapter_error": return .chapterFailed(index: e.index ?? 0)
        case "assembling", "mastering": return .assembling
        case "done": return .done(output: e.output ?? "", failed: e.failed_chapters ?? [])
        case "stopped": return .stopped
        // not VoiceStudio's text: it can quote the span that failed, i.e. script text, and ends up in the log
        case "error": throw Failure(message: "VoiceStudio: render error")
        default: return nil
        }
    }

    /// Moves the finished file out of VoiceStudio's outputs folder (no copy stays behind there).
    public func collect(_ output: String, to target: URL) async throws {
        // only ever touch outputs/story_<job>.<ext> – an empty or odd name must not reach removeItem
        guard output.range(of: #"^story_[A-Za-z0-9_-]+\.(m4b|mp3)$"#, options: .regularExpression) != nil else {
            throw Failure(message: "VoiceStudio: unexpected output name")
        }
        let src = Self.dataDir.appendingPathComponent("outputs").appendingPathComponent(output)
        let fm = FileManager.default
        let tmp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).part")
        try? fm.removeItem(at: tmp)
        defer { try? fm.removeItem(at: tmp) }   // gone after the move; left only if something failed
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue {
            try fm.copyItem(at: src, to: tmp)
        } else {
            let (data, resp) = try await session.data(from: Self.base.appendingPathComponent("audio").appendingPathComponent(output))
            try check(resp, data)
            try data.write(to: tmp)
        }
        if fm.fileExists(atPath: target.path) { try fm.trashItem(at: target, resultingItemURL: nil) }
        try fm.moveItem(at: tmp, to: target)
        try? fm.removeItem(at: src)
        Self.removeWorkFolder(job: String(output.dropFirst("story_".count).prefix { $0 != "." }))
    }

    /// The job's work folder holds the chapter list with the scene headings; not needed after the job.
    public static func removeWorkFolder(job: String) {
        guard job.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return }
        try? FileManager.default.removeItem(at: dataDir.appendingPathComponent("outputs/story_\(job)"))
    }

    /// VoiceStudio's own usage statistics setting (nil = unknown). Default is off; the app warns if it is on.
    public static func analyticsEnabled(prefs: URL = dataDir.appendingPathComponent("prefs.json")) -> Bool? {
        guard let d = try? Data(contentsOf: prefs),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return (j["analytics_enabled"] as? Bool) ?? false
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let h = resp as? HTTPURLResponse, h.statusCode != 200 else { return }
        // no response body: FastAPI's 422 detail repeats the input, i.e. script text
        throw Failure(message: "VoiceStudio: HTTP \(h.statusCode)")
    }
}
