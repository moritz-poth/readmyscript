import AppKit
import PDFKit

public enum PDFLines {
    public enum Failure: LocalizedError {
        case unreadable, locked, noText
        public var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "The PDF could not be read.")
            case .locked: return String(localized: "The PDF is password-protected.")
            case .noText: return String(localized: "The PDF contains no text (scanned pages are not supported yet).")
            }
        }
    }

    /// Every text line of the document, pages in order, lines top to bottom.
    public static func read(_ url: URL) throws -> (title: String?, lines: [TextLine]) {
        guard let doc = PDFDocument(url: url) else { throw Failure.unreadable }
        if doc.isLocked && !doc.unlock(withPassword: "") { throw Failure.locked }
        var out: [TextLine] = []
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let box = page.bounds(for: .mediaBox)
            guard let all = page.selection(for: box) else { continue }
            for sel in all.selectionsByLine() {
                guard let line = makeLine(sel, page: page, index: p, box: box) else { continue }
                out.append(line)
            }
        }
        // the content stream order is not always the reading order
        out.sort { (a: TextLine, b: TextLine) -> Bool in
            if a.page != b.page { return a.page < b.page }
            if abs(a.y - b.y) > 2 { return a.y < b.y }
            return a.x < b.x
        }
        if out.isEmpty { throw Failure.noText }
        let title = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil, out)
    }

    private static func makeLine(_ sel: PDFSelection, page: PDFPage, index: Int, box: CGRect) -> TextLine? {
        guard let attr = sel.attributedString, attr.length > 0 else { return nil }
        // Keep the dominant font size and colour; drop runs drawn much lighter (grey watermarks
        // that PDFKit merged into a real line).
        var text = "", sizes: [Double: Int] = [:], grays: [Double] = []
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { a, r, _ in
            let s = (attr.string as NSString).substring(with: r)
            // light AND colourless = watermark grey; light colours (yellow, light blue) stay
            let c = (a[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)
            let gray = c.map { $0.saturationComponent < 0.2 ? $0.brightnessComponent : 0 } ?? 0
            if gray > 0.55 && !s.trimmingCharacters(in: .whitespaces).isEmpty { grays.append(Double(gray)); return }
            text += s
            if let f = a[.font] as? NSFont { sizes[Double(f.pointSize).rounded(), default: 0] += s.count }
        }
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let b = sel.bounds(for: page)
        if text.isEmpty {
            // a line that is all light grey is a watermark – keep it marked so the cleaner can drop it
            guard let g = grays.max() else { return nil }
            return TextLine(page: index, text: sel.string ?? "", x: b.minX - box.minX, maxX: b.maxX - box.minX,
                            y: box.maxY - b.maxY, height: b.height, fontSize: 12, gray: g, pageWidth: box.width)
        }
        let size = sizes.max { $0.value < $1.value }?.key ?? 12
        return TextLine(page: index, text: text, x: b.minX - box.minX, maxX: b.maxX - box.minX,
                        y: box.maxY - b.maxY, height: b.height, fontSize: size, gray: 0, pageWidth: box.width)
    }
}
