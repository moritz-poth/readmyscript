import Foundation

/// Turns PDF text lines into screenplay elements. Works without fixed indents: the columns are
/// learned from the document, noise (watermarks, headers, page and scene numbers) is removed first.
public enum ScriptParser {
    public static func parse(_ url: URL) throws -> Script {
        let (title, lines) = try PDFLines.read(url)
        var script = parse(lines)
        script.title = title ?? url.deletingPathExtension().lastPathComponent
        return script
    }

    public static func parse(_ raw: [TextLine]) -> Script {
        let lines = clean(raw)
        let cols = Columns(lines)
        var els = classify(lines, cols)
        // A title page and notes before the first scene are not read.
        var skipped = 0
        if let first = els.firstIndex(where: { $0.kind == .scene }) {
            skipped = els[..<first].filter { $0.kind == .action || $0.kind == .dialogue }.count
            els.removeFirst(first)
        }
        var s = Script(title: "", elements: els)
        s.skippedBeforeFirstScene = skipped
        return s
    }

    // MARK: - Noise

    public static func clean(_ raw: [TextLine]) -> [TextLine] {
        let lines = raw.filter { !$0.text.isEmpty }
        guard !lines.isEmpty else { return [] }
        let size = median(lines.map(\.fontSize))
        let height = median(lines.map(\.height))
        let pages = Set(lines.map(\.page)).count

        // Text that sits at the same place on many pages: headers, footers, "CONFIDENTIAL", recipient
        // names, watermarks. Digits are masked so "Page 3" matches "Page 4".
        func key(_ l: TextLine) -> String {
            "\(Int((l.y / 8).rounded()))|" + l.text.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
        }
        var seen: [String: Set<Int>] = [:]
        for l in lines { seen[key(l), default: []].insert(l.page) }
        // short scripts: the text must be on every page; long ones: on 30 % (but at least 4)
        let repeatLimit = pages <= 4 ? pages : max(4, Int(Double(pages) * 0.3))

        return lines.compactMap { l in
            if l.gray > 0.55 { return nil }                                  // light grey
            if l.height > height * 2.5 { return nil }                        // rotated / huge
            if l.fontSize > size * 1.6 || l.fontSize < size * 0.5 { return nil }
            if pages >= 3, seen[key(l)]!.count >= repeatLimit { return nil }
            var l = l
            l.text = stripSceneNumbers(l.text)
            let t = l.text
            if t.isEmpty { return nil }
            if t.range(of: #"^[\d\s.,A-Z]{0,4}\d[\d\s.]*$"#, options: .regularExpression) != nil { return nil } // page / scene numbers
            if t.range(of: #"^(page|seite|p\.|s\.)\s*\d+(\s*(of|von|/)\s*\d+)?\.?$"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
            if t.range(of: #"^\((MORE|MEHR|WEITER|CONTINUED|FORTSETZUNG)\)$"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
            if t.range(of: #"^(CONTINUED|FORTSETZUNG)[:.]?$|^\(?(CONTINUED|FORTSETZUNG)\)?[:.]?\s*\(\d+\)$"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
            return l
        }
    }

    /// "12  INT. KITCHEN - NIGHT  12" → "INT. KITCHEN - NIGHT"; "12A INT. …" → "INT. …"
    static func stripSceneNumbers(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let m = t.range(of: #"^(\d+[A-Z]?)\s+(.+?)\s+\1\*?$"#, options: .regularExpression) {
            t = String(t[m]).replacingOccurrences(of: #"^(\d+[A-Z]?)\s+(.+?)\s+\1\*?$"#, with: "$2", options: .regularExpression)
        }
        // a leading number in front of a scene heading ("1. INNEN", "12A EXT.") is a scene number
        let lead = #"^\d+[A-Z]?[.)]?\s+(?=\S)"#
        if let r = t.range(of: lead, options: .regularExpression), isSceneHeading(String(t[r.upperBound...])) {
            t = String(t[r.upperBound...])
        }
        // trailing scene number after a heading
        if isSceneHeading(t), let r = t.range(of: #"\s+\d+[A-Z]?\*?$"#, options: .regularExpression) { t = String(t[..<r.lowerBound]) }
        return t
    }

    // MARK: - Columns

    /// Left edges of the action, dialogue and character-cue columns, learned from the document.
    public struct Columns {
        public var action: Double, dialogue: Double?, cue: Double?

        public init(_ lines: [TextLine]) {
            var cueXs: [Double] = [], dlgXs: [Double] = []
            for (i, l) in lines.enumerated() where i + 1 < lines.count {
                let n = lines[i + 1]
                guard ScriptParser.looksLikeCue(l.text), n.page == l.page, n.y - l.y < l.height * 2.2 else { continue }
                if isUpper(n.text) || n.x >= l.x { continue }
                cueXs.append(l.x)
                if !n.text.hasPrefix("(") { dlgXs.append(n.x) }
            }
            let all = lines.map(\.x)
            let left = all.min() ?? 0
            if cueXs.count >= 3, let c = mode(cueXs), let d = mode(dlgXs), c - d > 15 {
                cue = c; dialogue = d
                // action: the most common left edge clearly left of the dialogue column
                action = mode(all.filter { $0 < d - 15 }) ?? left
            } else {
                cue = nil; dialogue = nil
                action = mode(all) ?? left
            }
        }
    }

    // MARK: - Classification

    static func classify(_ lines: [TextLine], _ cols: Columns) -> [Element] {
        var out: [Element] = []
        // a blank line between paragraphs: clearly more than one line of text (leading up to ~1.3)
        let h = median(lines.map(\.height))
        let gapLimit = (h > 0 ? h : 12) * 1.6

        enum State { case none, dialogue(String) }
        var state = State.none
        var prev: TextLine?

        func append(_ kind: Kind, _ text: String, role: String?, page: Int, join: Bool) {
            if join, var last = out.last, last.kind == kind, last.role == role {
                last.text = joinLines(last.text, text)
                out[out.count - 1] = last
            } else {
                out.append(Element(kind: kind, text: text, role: role, page: page))
            }
        }

        for (i, l) in lines.enumerated() {
            let t = l.text
            let next = i + 1 < lines.count ? lines[i + 1] : nil
            let pageBreak = prev.map { $0.page != l.page } ?? false
            // with learned columns a paragraph runs on over a page break; without them a page break ends it
            let newParagraph = prev == nil || (pageBreak ? cols.dialogue == nil : l.y - prev!.y > gapLimit)
            defer { prev = l }

            if isSceneHeading(t) && (cols.dialogue == nil || l.x < cols.dialogue! - 15) {
                append(.scene, t, role: nil, page: l.page, join: false); state = .none; continue
            }
            // inside a speech only a new paragraph can be a transition ("ENDE DER DISKUSSION!" right after a cue is dialogue)
            if isTransition(t, l, cols), newParagraph || { if case .none = state { return true }; return false }() {
                append(.transition, t, role: nil, page: l.page, join: false); state = .none; continue
            }
            // "ANNA: Ich weiß es nicht." – cue and dialogue on one line (Word scripts)
            if let (cue, rest) = inlineCue(t), cols.cue == nil {
                let role = Role.normalize(cue)
                append(.character, cue, role: role, page: l.page, join: false)
                append(.dialogue, rest, role: role, page: l.page, join: false)
                state = .dialogue(role); continue
            }
            if isCue(l, next: next, cols) {
                let role = Role.normalize(t)
                append(.character, t, role: role, page: l.page, join: false)
                state = .dialogue(role); continue
            }
            if case .dialogue(let role) = state {
                let inColumn = cols.dialogue.map { l.x >= $0 - 15 } ?? true
                if inColumn && !newParagraph {
                    let lastKind = out.last?.kind
                    let openParen = lastKind == .parenthetical && !out.last!.text.contains(")")
                    if t.hasPrefix("(") || openParen {
                        // "(lacht) Na klar." – the direction ends at ")", the rest of the line is dialogue
                        let close = t.firstIndex(of: ")")
                        append(.parenthetical, close.map { String(t[...$0]) } ?? t, role: role, page: l.page, join: openParen)
                        let rest = close.map { t[t.index(after: $0)...].trimmingCharacters(in: .whitespaces) } ?? ""
                        if !rest.isEmpty { append(.dialogue, rest, role: role, page: l.page, join: false) }
                    } else {
                        append(.dialogue, t, role: role, page: l.page, join: lastKind == .dialogue)
                    }
                    continue
                }
                state = .none
            }
            append(.action, t, role: nil, page: l.page, join: !newParagraph && out.last?.kind == .action)
        }
        return out.map { var e = $0
            // directions inside a line of dialogue ("Ich weiß (zögert) nicht") are not read
            if e.kind == .dialogue { e.text = e.text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression) }
            if e.kind == .action || e.kind == .dialogue { e.text = tidy(e.text) }
            return e }
            .filter { !$0.text.isEmpty }
    }

    static func isCue(_ l: TextLine, next: TextLine?, _ cols: Columns) -> Bool {
        guard looksLikeCue(l.text), let n = next else { return false }
        if let cue = cols.cue, let d = cols.dialogue {
            // indented scripts: cue right of the dialogue column, followed by an indented line
            guard l.x > d + 10, abs(l.x - cue) < 60 || l.x > cols.action + 60 else { return false }
            guard n.x >= d - 15, n.x < l.x || n.text.hasPrefix("(") else { return false }
            return n.page != l.page || n.y - l.y < l.height * 2.2
        }
        // no columns: an upper-case name directly followed by normal text (or a shouted sentence)
        guard n.page == l.page, n.y - l.y < l.height * 2.2 else { return false }
        return !isUpper(n.text) || n.text.hasPrefix("(") || n.text.range(of: #"[.!?…]$"#, options: .regularExpression) != nil
    }

    static func looksLikeCue(_ t: String) -> Bool {
        let name = Role.normalize(t)
        guard !name.isEmpty, name.count <= 32, name.split(separator: " ").count <= 4 else { return false }
        guard isUpper(name), name.rangeOfCharacter(from: .letters) != nil else { return false }
        if isSceneHeading(t) || isTransitionWord(t) { return false }
        if name.hasSuffix(".") || name.hasSuffix("!") || name.hasSuffix("?") { return false }
        return true
    }

    static func inlineCue(_ t: String) -> (String, String)? {
        guard let r = t.range(of: #"^([A-ZÄÖÜ][A-ZÄÖÜß0-9 .'\-]{0,30}(\s*\([^)]*\))?):\s+(\S.*)$"#, options: .regularExpression),
              r.lowerBound == t.startIndex else { return nil }
        let colon = t.firstIndex(of: ":")!
        let cue = String(t[..<colon]), rest = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard looksLikeCue(cue), !isTransitionWord(cue) else { return nil }
        return (cue, rest)
    }

    static let sceneStart = #"^(INT|EXT|INT\.?\s*/\s*EXT|EXT\.?\s*/\s*INT|I\s*/\s*E|E\s*/\s*I|INNEN|AUSSEN|AUẞEN|AUßEN|INNEN\s*/\s*AUSSEN|AUSSEN\s*/\s*INNEN|I\s*/\s*A|A\s*/\s*I|EST)(\.|\s|/|-|–|$)"#
    static let timeOfDay = #"[-–—/,.]\s*(TAG|NACHT|ABEND|MORGEN|MITTAG|DÄMMERUNG|FRÜH|SPÄTER|KONTINUIERLICH|GLEICHZEITIG|DAY|NIGHT|EVENING|MORNING|AFTERNOON|DAWN|DUSK|LATER|CONTINUOUS|SAME|MOMENTS LATER)\b[^a-zäöü]*$"#

    static func isSceneHeading(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespaces)
        guard s.count < 120 else { return false }
        if s.range(of: sceneStart, options: [.regularExpression, .caseInsensitive]) != nil, isUpper(s) || s.hasPrefix("INT") || s.hasPrefix("EXT") { return true }
        // "1. KÜCHE – INNEN/TAG", "WOHNUNG ANNA – NACHT"
        return isUpper(s) && s.range(of: timeOfDay, options: .regularExpression) != nil
            && s.range(of: #"\b(INNEN|AUSSEN|AUßEN|INT|EXT)\b"#, options: .regularExpression) != nil
    }

    static func isTransitionWord(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespaces)
        // multi-word transitions may go on ("CUT TO: KITCHEN"); bare words only as the whole line with ":" or "."
        if s.range(of: #"^(CUT TO|SMASH CUT|MATCH CUT|JUMP CUT|HARD CUT|FADE (IN|OUT|TO)|DISSOLVE TO|SCHNITT AUF|HARTER SCHNITT|ÜBERBLENDE AUF|ÜBERBLENDUNG|ABBLENDE AUF|INTERCUT|ZWISCHENSCHNITT)\b"#, options: .regularExpression) != nil { return true }
        return s.range(of: #"^(SCHNITT|ABBLENDE|AUFBLENDE|ÜBERBLENDE|BLENDE|ABBLENDEN|AUFBLENDEN|SCHWARZBILD|SCHWARZ|BLACK|CUT|ENDE|THE END|FADE OUT)\s*[:.]$|^(ABBLENDE|AUFBLENDE|SCHWARZBILD|THE END|FADE OUT)$"#,
                       options: .regularExpression) != nil
    }

    static func isTransition(_ t: String, _ l: TextLine, _ cols: Columns) -> Bool {
        guard isUpper(t), t.count <= 40 else { return false }
        if isTransitionWord(t) { return true }
        // right-aligned upper-case line ending in a colon ("BACK TO:")
        return t.hasSuffix(":") && (l.x > (cols.cue ?? cols.action + 200) || l.maxX > l.pageWidth * 0.75)
    }

    // MARK: - Text

    public static func isUpper(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 1 else { return false }
        let lower = s.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) && $0 != "ß" }
        return lower.isEmpty
    }

    static func joinLines(_ a: String, _ b: String) -> String {
        // "Kü-" + "che" → "Küche"; "nicht -" + "aber" keeps the dash
        if a.hasSuffix("-"), a.dropLast().last?.isLetter == true, b.first?.isLowercase == true {
            return String(a.dropLast()) + b
        }
        return a + " " + b
    }

    /// Long upper-case words in running text (character introductions like "ANNA (30) betritt …")
    /// read better capitalised; short ones (TV, BKA) are probably acronyms and stay.
    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: #" ([,.!?;:…])"#, with: "$1", options: .regularExpression)
        // a whole shouted line: every word, not only the long ones
        let rx = try! NSRegularExpression(pattern: isUpper(t) ? #"\b[A-ZÄÖÜ][A-ZÄÖÜẞ]+\b"# : #"\b[A-ZÄÖÜ][A-ZÄÖÜẞ]{3,}\b"#)
        for m in rx.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            let r = Range(m.range, in: t)!
            t.replaceSubrange(r, with: t[r].prefix(1) + t[r].dropFirst().lowercased())
        }
        return t
    }
}

func median(_ v: [Double]) -> Double {
    guard !v.isEmpty else { return 0 }
    let s = v.sorted()
    return s[s.count / 2]
}

/// Most common value, grouped in 4-point bins (indents differ by fractions of a point).
func mode(_ v: [Double]) -> Double? {
    guard !v.isEmpty else { return nil }
    var bins: [Int: [Double]] = [:]
    for x in v { bins[Int((x / 4).rounded()), default: []].append(x) }
    return bins.max { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }.map { median($0.value) }
}
