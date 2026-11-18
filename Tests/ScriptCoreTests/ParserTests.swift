import Foundation
import Testing
@testable import ScriptCore

struct ParserTests {
    typealias E = FakeScript.El

    /// Three scenes, long enough to run over several pages, with a dialogue split by a page break.
    static let sample: [E] = {
        var els: [E] = [.transition("FADE IN:"),
                        .scene("1. INNEN. KÜCHE – NACHT"),
                        .action("ANNA (30) steht am Fenster. Draußen regnet es seit Stunden."),
                        .character("ANNA"), .paren("leise"), .dialogue("Ich habe ihn gesehen."),
                        .character("BEN (O.S.)"), .dialogue("Wen?"),
                        .transition("SCHNITT AUF:"),
                        .scene("2. AUSSEN. STRASSE – TAG")]
        for i in 1...14 {
            els.append(.action("Absatz \(i): Autos fahren vorbei, ein Hund bellt, Ben läuft über die nasse Straße zum Kiosk."))
            els.append(.character("BEN"))
            els.append(.dialogue("Satz \(i). Ich weiß nicht, was sie meint, aber ich werde es herausfinden, egal wie lange es dauert."))
        }
        els.append(.scene("3. INT. KIOSK - CONTINUOUS"))
        els.append(.character("VERKÄUFERIN"))
        els.append(.dialogue("Was darf es sein?"))
        return els
    }()

    // temp files are left to the system's temp cleanup

    func pdf(_ fs: FakeScript, _ els: [E] = sample) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rms-\(UUID().uuidString).pdf")
        fs.pdf(els).write(to: url)
        return url
    }

    func check(_ s: Script) {
        let scenes = s.elements.filter { $0.kind == .scene }.map(\.text)
        #expect(scenes == ["INNEN. KÜCHE – NACHT", "AUSSEN. STRASSE – TAG", "INT. KIOSK - CONTINUOUS"])
        #expect(s.roles.map(\.name) == ["BEN", "ANNA", "VERKÄUFERIN"])
        let ben = s.elements.filter { $0.kind == .dialogue && $0.role == "BEN" }
        #expect(ben.first?.text == "Wen?")
        // every BEN sentence arrives complete, also the one split by a page break
        for i in 1...14 {
            #expect(ben.contains { $0.text == "Satz \(i). Ich weiß nicht, was sie meint, aber ich werde es herausfinden, egal wie lange es dauert." }, Comment(rawValue: "Satz \(i) missing or broken: \(ben.map(\.text))"))
        }
        let anna = s.elements.first { $0.kind == .dialogue && $0.role == "ANNA" }
        #expect(anna?.text == "Ich habe ihn gesehen.")
        #expect(s.elements.contains { $0.kind == .parenthetical && $0.text == "(leise)" })
        let actions = s.elements.filter { $0.kind == .action }
        #expect(actions.first?.text == "Anna (30) steht am Fenster. Draußen regnet es seit Stunden.")
        #expect(actions.count == 15, Comment(rawValue: actions.map(\.text).joined(separator: "\n")))
        // no noise in anything that is spoken
        for e in s.elements where e.kind == .action || e.kind == .dialogue {
            for noise in ["KOPIE", "VERTRAULICH", "MORE", "CONT'D", "WEITER", "Kopie", "Vertraulich"] {
                #expect(!(e.text.contains(noise)), Comment(rawValue: "noise '\(noise)' in: \(e.text)"))
            }
            #expect(e.text.range(of: #"^\d+\.?$"#, options: .regularExpression) == nil)
        }
        // title page and FADE IN are dropped (nothing before the first scene)
        #expect(s.elements.first?.kind == .scene)
    }

    @Test func testFinalDraftLayout() throws {
        var fs = FakeScript()
        fs.titlePage = ["DER REGEN", "von", "Autorin"]
        check(try ScriptParser.parse(pdf(fs)))
    }

    @Test func testWatermarkHeaderSceneNumbers() throws {
        var fs = FakeScript()
        fs.titlePage = ["DER REGEN"]
        fs.header = "VERTRAULICH – Kopie für Testperson 07"
        fs.watermark = "KOPIE 07 – TESTPERSON"
        fs.sceneNumbers = true
        let s = try ScriptParser.parse(pdf(fs))
        #expect(Set(s.elements.map(\.page)).count > 2, Comment(rawValue: "sample must span several pages"))
        check(s)
    }

    @Test func testGermanWordA4Layout() throws {
        var fs = FakeScript(layout: .wordA4)
        fs.more = ("(WEITER)", "(FORTS.)")
        fs.watermark = "VERTRAULICH"
        check(try ScriptParser.parse(pdf(fs)))
    }

    /// Everything at one left edge: names in capitals, dialogue below, also "NAME: text" lines.
    @Test func testNoIndents() throws {
        let lines: [(String)] = [
            "INNEN. BÜRO – TAG", "",
            "Ein leeres Büro. Das Telefon klingelt.", "",
            "MARIE", "Hallo? Wer ist da?", "",
            "TOM: Ich bin es.", "",
            "Marie legt auf.",
        ]
        var y = 72.0, tl: [TextLine] = []
        for t in lines {
            if !t.isEmpty { tl.append(TextLine(page: 0, text: t, x: 72, maxX: 72 + Double(t.count) * 7.2, y: y, height: 12)) }
            y += 12
        }
        let s = ScriptParser.parse(tl)
        #expect(s.elements.map(\.kind) == [.scene, .action, .character, .dialogue, .character, .dialogue, .action])
        #expect(s.roles.map(\.name).sorted() == ["MARIE", "TOM"])
        #expect(s.elements.last?.text == "Marie legt auf.")
    }

    /// German scripts often put the direction and the dialogue on one line.
    @Test func testInlineParenthetical() throws {
        let els: [E] = [.scene("INNEN. FLUR – TAG"), .character("ANNA"),
                        .dialogue("(lacht) Na klar, ich komme mit, aber nur bis zur Tür."),
                        .character("BEN"), .dialogue("Ich weiß (zögert), nicht."), .action("Sie gehen.")]
        let s = try ScriptParser.parse(pdf(FakeScript(), els))
        #expect(s.elements.map(\.kind) == [.scene, .character, .parenthetical, .dialogue, .character, .dialogue, .action])
        #expect(s.elements[2].text == "(lacht)")
        #expect(s.elements[3].text == "Na klar, ich komme mit, aber nur bis zur Tür.")
        #expect(s.elements[5].text == "Ich weiß, nicht.")
    }

    /// A role named like a transition word, and shouted dialogue that starts with one.
    @Test func testTransitionWordsAreNotGreedy() throws {
        let els: [E] = [.scene("INNEN. SET – TAG"), .character("SCHWARZ"), .dialogue("Alle auf Position."),
                        .character("ANNA"), .dialogue("ENDE DER DISKUSSION!"), .transition("SCHNITT AUF:"), .action("Stille.")]
        let s = try ScriptParser.parse(pdf(FakeScript(), els))
        #expect(s.roles.map(\.name).sorted() == ["ANNA", "SCHWARZ"])
        #expect(s.elements.filter { $0.kind == .dialogue }.map(\.text) == ["Alle auf Position.", "Ende Der Diskussion!"])
        #expect(s.elements.filter { $0.kind == .transition }.map(\.text) == ["SCHNITT AUF:"])
    }

    @Test func testRoleNames() {
        #expect(Role.normalize("ANNA (V.O.)") == "ANNA")
        #expect(Role.normalize("ANNA (CONT'D)") == "ANNA")
        #expect(Role.normalize("ANNA (FORTS.)") == "ANNA")
        #expect(Role.normalize("ANNA (OFF)") == "ANNA")
        #expect(Role.normalize("ANNA CONT'D") == "ANNA")
        #expect(Role.normalize("DR.  MÜLLER:") == "DR. MÜLLER")
    }

    @Test func testSceneHeadings() {
        for h in ["INT. KITCHEN - NIGHT", "EXT. STREET – DAY", "INNEN. KÜCHE – NACHT", "I/A AUTO – FAHREND – TAG",
                  "AUSSEN – WALD – DÄMMERUNG", "INT./EXT. CAR - MOVING - DAY", "1. KÜCHE – INNEN/TAG"] {
            #expect(ScriptParser.isSceneHeading(h), Comment(rawValue: h))
        }
        for t in ["ANNA", "Innen ist es dunkel.", "INTERESSANT!", "EXTRA"] { #expect(!(ScriptParser.isSceneHeading(t)), Comment(rawValue: t)) }
        #expect(ScriptParser.stripSceneNumbers("12  INT. KITCHEN - NIGHT  12") == "INT. KITCHEN - NIGHT")
        #expect(ScriptParser.stripSceneNumbers("12A INT. KITCHEN - NIGHT") == "INT. KITCHEN - NIGHT")
        #expect(ScriptParser.stripSceneNumbers("3 Äpfel liegen da.") == "3 Äpfel liegen da.")
    }

    @Test func testTextTidy() {
        #expect(ScriptParser.joinLines("Kü-", "che") == "Küche")
        #expect(ScriptParser.joinLines("nicht -", "aber") == "nicht - aber")
        #expect(ScriptParser.tidy("MARIE (40) sieht fern, TV läuft.") == "Marie (40) sieht fern, TV läuft.")
    }
}

struct DemoScriptTests {
    /// The self-test relies on these numbers.
    @Test func demoScriptsParse() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rms-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for url in DemoScript.write(to: dir) {
            let s = try ScriptParser.parse(url)
            #expect(s.sceneCount == DemoScript.scenes)
            #expect(s.roles.map(\.name).sorted() == DemoScript.roles)
            #expect(!s.elements.contains { $0.text.contains("SELF-TEST") })   // watermark and header gone
        }
    }
}
