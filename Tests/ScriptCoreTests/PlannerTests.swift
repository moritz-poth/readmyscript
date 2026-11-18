import Foundation
import Testing
@testable import ScriptCore

struct PlannerTests {
    let script = Script(title: "Test", elements: [
        Element(kind: .scene, text: "INNEN. KÜCHE – NACHT"),
        Element(kind: .action, text: "Anna steht am Fenster."),
        Element(kind: .character, text: "ANNA", role: "ANNA"),
        Element(kind: .parenthetical, text: "(leise)", role: "ANNA"),
        Element(kind: .dialogue, text: "Ich habe ihn gesehen.", role: "ANNA"),
        Element(kind: .dialogue, text: "Wirklich.", role: "ANNA"),
        Element(kind: .character, text: "BEN", role: "BEN"),
        Element(kind: .dialogue, text: "Wen?", role: "BEN"),
        Element(kind: .transition, text: "SCHNITT AUF:"),
        Element(kind: .scene, text: "AUSSEN. STRASSE – TAG"),
        Element(kind: .dialogue, text: "Nur Ben spricht hier.", role: "BEN"),
        Element(kind: .scene, text: "INNEN. LEER – TAG"),
        Element(kind: .action, text: "Niemand liest das."),
    ])

    @Test func testPlan() {
        let cast = Cast(narrator: "n", roles: ["ANNA": "a", "BEN": "b"], overrides: [12: .silent])
        let plan = RenderPlan.make(script, cast: cast, language: "German")
        #expect(plan.chapters.map(\.title) == ["INNEN. KÜCHE – NACHT", "AUSSEN. STRASSE – TAG"]) // empty scene dropped
        let s = plan.chapters[0].spans
        #expect(s.map(\.voice_id) == ["n", "a", "a", "b"])
        #expect(s.map(\.text) == ["Anna steht am Fenster.", "Ich habe ihn gesehen.", "Wirklich.", "Wen?"])
        let p = Pauses()
        #expect(s.map(\.pause_ms_after) == [p.speakerChange, p.sameVoice, p.speakerChange, p.sceneEnd])
        #expect(plan.default_voice == "n")
        #expect(plan.language == "German")
    }

    @Test func testSilentRoleAndNarratorOverride() {
        let cast = Cast(narrator: "n", roles: ["ANNA": String?.none, "BEN": "b"], overrides: [7: .narrator])
        let plan = RenderPlan.make(script, cast: cast, language: nil)
        #expect(plan.chapters[0].spans.map(\.voice_id) == ["n", "n"])
        #expect(plan.chapters[0].spans.last?.text == "Wen?")
    }

    @Test func testSuggest() {
        let cast = Cast.suggest(for: script, voices: ["v1", "v2", "v3"])
        #expect(cast.narrator == "v1")
        #expect(cast.roles["ANNA"] == "v2")   // most lines first
        #expect(cast.roles["BEN"] == "v3")
        #expect(cast.unassigned(in: script).isEmpty)
    }

    @Test func testSuggestNeverSharesAVoice() {
        let cast = Cast.suggest(for: script, voices: ["v1", "v2"])
        #expect(cast.narrator == "v1")
        #expect(cast.roles["ANNA"] == "v2")
        #expect(cast.roles["BEN"] == nil)                 // no voice left: unassigned, not reused
        #expect(cast.unassigned(in: script) == ["BEN"])
        #expect(cast.users(of: "v1", except: "BEN") == [""])
        #expect(cast.users(of: "v2", except: "ANNA").isEmpty)
        var c = cast; c.roles["BEN"] = .some(nil)        // "Don't read" is a decision, not unassigned
        #expect(c.unassigned(in: script).isEmpty)
    }

    @Test func testJSONShape() throws {
        let plan = RenderPlan.make(script, cast: Cast(narrator: "n"), language: "English")
        let j = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as! [String: Any]
        #expect(j["format"] as? String == "m4b")
        let ch = (j["chapters"] as! [[String: Any]])[0]
        #expect((ch["spans"] as! [[String: Any]])[0]["pause_ms_after"] != nil)
    }

    @Test func testEvents() throws {
        #expect(try VoiceStudio.event(Data(#"{"type":"started","job_id":"x","chapters":3}"#.utf8)) == .started(chapters: 3, job: "x"))
        #expect(try VoiceStudio.event(Data(#"{"type":"chapter","index":0,"total":3}"#.utf8)) == .chapterDone(index: 0, total: 3))
        #expect(try VoiceStudio.event(Data(#"{"type":"done","output":"story_1.m4b","chapters":3,"failed_chapters":[]}"#.utf8)) == .done(output: "story_1.m4b", failed: []))
        #expect(throws: (any Error).self) { try VoiceStudio.event(Data(#"{"type":"error","error":"boom"}"#.utf8)) }
        #expect(try VoiceStudio.event(Data(#"{"type":"heartbeat"}"#.utf8)) == nil)
    }

    /// collect must never touch anything but outputs/story_<job>.<ext> (an empty name once meant the whole folder).
    @Test func testCollectRejectsOddNames() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("rms-\(UUID()).m4b")
        for bad in ["", ".", "..", "../prefs.json", "story_x/../../prefs.json", "longform_cache", "story_1.wav"] {
            await #expect(throws: (any Error).self) { try await VoiceStudio().collect(bad, to: target) }
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func testAnalyticsSetting() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("rms-prefs-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: f) }
        try Data(#"{"analytics_enabled": true}"#.utf8).write(to: f)
        #expect(VoiceStudio.analyticsEnabled(prefs: f) == true)
        try Data(#"{"theme": "dark"}"#.utf8).write(to: f)
        #expect(VoiceStudio.analyticsEnabled(prefs: f) == false)
    }

    /// Legal requirement: the script must never leave the computer. No source file may name any
    /// network address except the loopback VoiceStudio server (and the coffee/about links do not exist here).
    @Test func testOnlyKnownAddressesInSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!(files.isEmpty))
        let rx = try NSRegularExpression(pattern: #"[a-z]+://[^\s"\\)]+"#)
        for f in files {
            let s = try String(contentsOf: f, encoding: .utf8)
            for m in rx.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                let u = String(s[Range(m.range, in: s)!])
                // the app talks to VoiceStudio on this Mac and, for updates only, to this project's GitHub releases;
                // the other addresses are web pages it hands to the browser (source code, license, coffee)
                let updater = f.lastPathComponent == "Updater.swift"
                let ok = u.hasPrefix("http://127.0.0.1:3900") || u.hasPrefix("file://")
                    || (updater && u.hasPrefix("https://api.github.com/repos/moritz-poth/readmyscript/releases"))
                    || u.hasPrefix("https://github.com/moritz-poth/readmyscript")
                    || u == "https://www.gnu.org/licenses/gpl-3.0.html" || u == "https://buymeacoffee.com/moritzpoth"
                #expect(ok, Comment(rawValue: "\(f.lastPathComponent): \(u)"))
            }
        }
    }
}
