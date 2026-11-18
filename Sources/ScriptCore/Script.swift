import Foundation

/// One line of text as it sits on a PDF page (top-left origin, points).
public struct TextLine: Equatable, Sendable {
    public var page: Int
    public var text: String
    public var x: Double
    public var maxX: Double
    public var y: Double          // top edge, from the page top
    public var height: Double
    public var fontSize: Double
    public var gray: Double       // 0 = black, 1 = white
    public var pageWidth: Double

    public init(page: Int, text: String, x: Double, maxX: Double, y: Double, height: Double,
                fontSize: Double = 12, gray: Double = 0, pageWidth: Double = 612) {
        self.page = page; self.text = text; self.x = x; self.maxX = maxX; self.y = y
        self.height = height; self.fontSize = fontSize; self.gray = gray; self.pageWidth = pageWidth
    }
}

public enum Kind: String, Codable, Sendable, CaseIterable {
    case scene, action, character, parenthetical, dialogue, transition
}

/// A paragraph of the screenplay. `role` is set for character cues, parentheticals and dialogue.
public struct Element: Equatable, Sendable, Identifiable {
    public var id: Int
    public var kind: Kind
    public var text: String
    public var role: String?
    public var page: Int

    public init(id: Int = 0, kind: Kind, text: String, role: String? = nil, page: Int = 0) {
        self.id = id; self.kind = kind; self.text = text; self.role = role; self.page = page
    }
}

public struct Script: Sendable {
    public var title: String
    public var elements: [Element]
    /// Spoken paragraphs before the first scene heading (title page, notes) – not read.
    public var skippedBeforeFirstScene = 0

    public init(title: String, elements: [Element]) {
        self.title = title
        self.elements = elements.enumerated().map { var e = $1; e.id = $0; return e }
    }

    /// Roles with their number of dialogue paragraphs, most lines first.
    public var roles: [(name: String, lines: Int)] {
        var count: [String: Int] = [:], order: [String] = []
        for e in elements where e.kind == .dialogue {
            guard let r = e.role else { continue }
            if count[r] == nil { order.append(r) }
            count[r, default: 0] += 1
        }
        return order.map { ($0, count[$0]!) }.sorted { $0.lines != $1.lines ? $0.lines > $1.lines : $0.name < $1.name }
    }

    public var sceneCount: Int { elements.filter { $0.kind == .scene }.count }

    /// All spoken text, for language detection.
    public var spokenSample: String {
        elements.filter { $0.kind == .action || $0.kind == .dialogue }.prefix(80).map(\.text).joined(separator: " ")
    }
}

public enum Role {
    /// "ANNA (V.O.)", "ANNA (CONT'D)", "ANNA (FORTS.)", "ANNA:" → "ANNA"
    public static func normalize(_ cue: String) -> String {
        var s = cue.replacingOccurrences(of: #"\([^)]*\)?"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(CONT'?D|CONT\.|FORTS\.?|WEITER|V\.?O\.?|O\.?S\.?|O\.?C\.?|OFF)\s*$"#, with: " ",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"[:\s]+$"#, with: "", options: .regularExpression)
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
