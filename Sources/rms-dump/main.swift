import Foundation
import ScriptCore

// Usage: rms-dump <script.pdf> [--lines | --stats]   – what the parser makes of a PDF
// --stats prints numbers only (no script text, no names): safe to share when checking real scripts.
let args = CommandLine.arguments.dropFirst()
guard let path = args.first else { print("usage: rms-dump <script.pdf> [--lines]"); exit(2) }
let url = URL(fileURLWithPath: path)
do {
    if args.contains("--lines") {
        for l in try PDFLines.read(url).lines {
            print(String(format: "p%-3d x%6.1f y%6.1f h%5.1f f%4.1f g%.2f | ", l.page + 1, l.x, l.y, l.height, l.fontSize, l.gray) + l.text)
        }
        exit(0)
    }
    if args.contains("--stats") {
        let (_, lines) = try PDFLines.read(url)
        let s = ScriptParser.parse(lines)
        let kept = ScriptParser.clean(lines).count
        let pages = Set(lines.map(\.page)).count
        print("pages \(pages) · lines \(lines.count) · removed as noise \(lines.count - kept)")
        let c = ScriptParser.Columns(ScriptParser.clean(lines))
        print(String(format: "columns: action %.0f · dialogue %@ · cue %@", c.action, c.dialogue.map { String(format: "%.0f", $0) } ?? "–", c.cue.map { String(format: "%.0f", $0) } ?? "–"))
        for k in Kind.allCases { print("  \(k.rawValue): \(s.elements.filter { $0.kind == k }.count)") }
        let roles = s.roles
        print("roles \(roles.count) · lines per role (desc): \(roles.map { String($0.lines) }.joined(separator: " "))")
        print("roles with one line: \(roles.filter { $0.lines == 1 }.count)")
        let words = s.elements.filter { $0.kind == .action || $0.kind == .dialogue }.map { $0.text.split(separator: " ").count }
        print("spoken words \(words.reduce(0, +)) · ~\(words.reduce(0, +) / 150) min")
        // suspicious: spoken text in capitals, very long dialogue, short upper-case action lines
        print("suspicious: upper-case spoken \(s.elements.filter { ($0.kind == .action || $0.kind == .dialogue) && ScriptParser.isUpper($0.text) && $0.text.count > 3 }.count)",
              "· dialogue >120 words \(s.elements.filter { $0.kind == .dialogue && $0.text.split(separator: " ").count > 120 }.count)",
              "· action ending in ':' \(s.elements.filter { $0.kind == .action && $0.text.hasSuffix(":") }.count)")
        var after: [String: Int] = [:]
        for (i, e) in s.elements.enumerated() where e.kind == .character {
            let n = s.elements.dropFirst(i + 1).prefix(2).map(\.kind.rawValue).joined(separator: ">")
            after[n, default: 0] += 1
        }
        print("after a cue:", after.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        // text shape only (letters → X/x, digits → 9), short lines – shows the format, not the content
        func shape(_ t: String) -> String { String(t.prefix(40).map { $0.isUppercase ? "X" : $0.isLowercase ? "x" : $0.isNumber ? "9" : $0 }) }
        let odd = s.elements.enumerated().filter { i, e in e.kind == .character && (i + 1 == s.elements.count || s.elements[i + 1].kind != .dialogue && s.elements[i + 1].kind != .parenthetical) }
        print("cue shapes without dialogue:", Set(odd.map { shape($0.element.text) }).sorted().prefix(15).joined(separator: " | "))
        print("action ':' shapes:", Set(s.elements.filter { $0.kind == .action && $0.text.hasSuffix(":") }.map { shape(String($0.text.suffix(20))) }).sorted().prefix(10).joined(separator: " | "))
        exit(0)
    }
    if let i = args.firstIndex(of: "--render"), i + 1 < args.endIndex {
        // end-to-end check with VoiceStudio: first voice narrates, the others share the roles
        let s = try ScriptParser.parse(url)
        let studio = VoiceStudio()
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let voices = try await studio.voices()
                print("voices:", voices.count)
                let plan = RenderPlan.make(s, cast: Cast.suggest(for: s, voices: voices.map(\.id)), language: nil)
                print("chapters \(plan.chapters.count), spans \(plan.spanCount)")
                for try await ev in studio.render(plan) {
                    print(ev)
                    if case .done(let out, _) = ev { try await studio.collect(out, to: URL(fileURLWithPath: args[i + 1])) }
                }
            } catch { print("error:", error.localizedDescription) }
            sem.signal()
        }
        sem.wait()
        exit(0)
    }
    let s = try ScriptParser.parse(url)
    print("TITLE:", s.title, "· scenes:", s.sceneCount)
    for e in s.elements {
        let tag = e.kind.rawValue.prefix(5).uppercased()
        print("p\(e.page + 1) \(tag)\(e.role.map { " [\($0)]" } ?? ""): \(e.text)")
    }
    print("ROLES:", s.roles.map { "\($0.name) \($0.lines)" }.joined(separator: ", "))
} catch {
    print("error:", error.localizedDescription); exit(1)
}
