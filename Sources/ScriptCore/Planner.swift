import Foundation

/// Who speaks what. `nil` voice = not spoken.
public struct Cast: Codable, Equatable, Sendable {
    public var narrator: String?
    public var roles: [String: String?]
    /// Per-element corrections from the preview.
    public var overrides: [Int: Override]

    public enum Override: String, Codable, Sendable { case narrator, silent }

    public init(narrator: String? = nil, roles: [String: String?] = [:], overrides: [Int: Override] = [:]) {
        self.narrator = narrator; self.roles = roles; self.overrides = overrides
    }

    /// The voice that reads this element, or nil when it is not spoken.
    public func voice(for e: Element) -> String? {
        switch overrides[e.id] {
        case .silent: return nil
        case .narrator: return narrator
        case nil: break
        }
        switch e.kind {
        case .action: return narrator
        case .dialogue: return e.role.flatMap { roles[$0] ?? nil }
        default: return nil
        }
    }

    /// Gives each voice to at most one part: the narrator gets the first, then roles with the most lines.
    /// Roles left over get no entry (`unassigned`) – sharing a voice is only ever the user's explicit choice.
    public static func suggest(for script: Script, voices: [String]) -> Cast {
        guard !voices.isEmpty else { return Cast() }
        var cast = Cast(narrator: voices[0])
        for (r, v) in zip(script.roles, voices.dropFirst()) { cast.roles[r.name] = .some(v) }
        return cast
    }

    /// Roles that have neither a voice nor "Don't read" yet – their lines would silently go missing.
    public func unassigned(in script: Script) -> [String] {
        script.roles.map(\.name).filter { roles[$0] == nil }
    }

    /// Who already speaks with this voice ("" = narrator), apart from `except` (nil = narrator).
    public func users(of voice: String, except: String?) -> [String] {
        var u = roles.filter { $0.value == voice && $0.key != except }.map(\.key).sorted()
        if narrator == voice && except != nil { u.insert("", at: 0) }
        return u
    }
}

public struct Pauses: Codable, Equatable, Sendable {
    public var sameVoice = 500, speakerChange = 300, sceneEnd = 1500
    public init() {}
}

/// Body of VoiceStudio's POST /longform/render.
public struct RenderPlan: Encodable, Sendable {
    public struct Span: Encodable, Sendable, Equatable {
        public var voice_id: String
        public var text: String
        public var pause_ms_after: Int
    }
    public struct Chapter: Encodable, Sendable { public var title: String; public var spans: [Span] }

    public var chapters: [Chapter]
    public var default_voice: String?
    public var language: String?
    public var format = "m4b"
    public var bitrate = "128k"
    public var metadata: [String: String]

    public var spanCount: Int { chapters.reduce(0) { $0 + $1.spans.count } }

    /// `language`: "German", "English" or nil (VoiceStudio picks per voice).
    public static func make(_ script: Script, cast: Cast, language: String?, pauses: Pauses = Pauses()) -> RenderPlan {
        var chapters: [Chapter] = []
        var current: Chapter? = nil
        func close() {
            if var c = current, !c.spans.isEmpty {
                c.spans[c.spans.count - 1].pause_ms_after = pauses.sceneEnd
                chapters.append(c)
            }
            current = nil
        }
        for e in script.elements {
            if e.kind == .scene {
                close(); current = Chapter(title: e.text, spans: []); continue
            }
            guard let voice = cast.voice(for: e) else { continue }
            if current == nil { current = Chapter(title: script.title, spans: []) }
            if let last = current!.spans.last {
                current!.spans[current!.spans.count - 1].pause_ms_after = last.voice_id == voice ? pauses.sameVoice : pauses.speakerChange
            }
            current!.spans.append(Span(voice_id: voice, text: e.text, pause_ms_after: 0))
        }
        close()
        return RenderPlan(chapters: chapters, default_voice: cast.narrator, language: language,
                          metadata: ["title": script.title, "genre": "Screenplay"])
    }
}
