import Foundation
import Testing

/// Every UI text of the app exists in German, French and Spanish (English texts are the keys), and so does the manual.
struct LocalizationTests {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Keys used in the sources: Text("…"), Button("…"), String(localized: "…"), hint("…"), SwitchRow(title: "…"), add("…")
    func keys() throws -> Set<String> {
        let dir = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && !$0.path.contains("rms-dump") }
        let src = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        let rx = try NSRegularExpression(pattern: #"(?:Text|Button|localized:|Window|hint|title:|add|Label|fail)\(?\s*"((?:[^"\\]|\\.)*)""#)
        var out = Set<String>()
        for m in rx.matches(in: src, range: NSRange(src.startIndex..., in: src)) {
            var key = String(src[Range(m.range(at: 1), in: src)!])
            if key.hasPrefix("\\(") && key.hasSuffix(")") && key.filter({ $0 == "(" }).count == 1 { continue } // a variable
            if key.isEmpty || key.hasPrefix("http") || key.contains("/") && !key.contains(" ") { continue }
            key = key.replacingOccurrences(of: #"\\\((failed|done|total|open|r\.lines|script\.sceneCount|script\.roles\.count|script\.skippedBeforeFirstScene|min\(done \+ 1, total\)|plan\.chapters\.count|plan\.spanCount|voices\.count|wav\.count / 1024|fail|pass|skip|test\.results[^)]*\)\.count)\)"#, with: "%lld", options: .regularExpression)
            key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression)
            key = key.replacingOccurrences(of: #"\\""#, with: "\"", options: .regularExpression)
            out.insert(key)
        }
        return out
    }

    @Test(arguments: ["de", "fr", "es"]) func complete(_ lang: String) throws {
        let table = NSDictionary(contentsOf: root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")) as? [String: String] ?? [:]
        #expect(!table.isEmpty)
        let missing = try keys().filter { table[$0] == nil }.sorted()
        #expect(missing.isEmpty, "missing in \(lang): \(missing)")
    }

    @Test func manualInEveryLanguage() throws {
        for lang in ["en", "de", "fr", "es"] {
            let text = try String(contentsOf: root.appendingPathComponent("Resources/help/\(lang).md"), encoding: .utf8)
            #expect(text.hasPrefix("# "), "\(lang).md")
        }
    }
}
