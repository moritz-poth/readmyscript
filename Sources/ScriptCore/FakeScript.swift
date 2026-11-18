import CoreGraphics
import CoreText
import Foundation

/// Draws synthetic screenplay PDFs for tests and the self-test – never a real script in the repo.
public struct FakePDF {
    public struct Item {
        public var text: String
        public var x: CGFloat
        public var y: CGFloat          // top of the line, from the page top
        public var size: CGFloat = 12
        public var font = "Courier"
        public var gray: CGFloat = 0   // 0 = black
        public var alpha: CGFloat = 1
        public var angle: CGFloat = 0  // degrees, counter-clockwise

        public init(text: String, x: CGFloat, y: CGFloat, size: CGFloat = 12, font: String = "Courier", gray: CGFloat = 0, alpha: CGFloat = 1, angle: CGFloat = 0) {
            self.text = text; self.x = x; self.y = y; self.size = size; self.font = font; self.gray = gray; self.alpha = alpha; self.angle = angle
        }
    }
    public var width: CGFloat = 612, height: CGFloat = 792
    public var pages: [[Item]] = []

    public init(width: CGFloat = 612, height: CGFloat = 792, pages: [[Item]] = []) {
        self.width = width; self.height = height; self.pages = pages
    }

    public func write(to url: URL) {
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for page in pages {
            ctx.beginPDFPage(nil)
            for it in page {
                let font = CTFontCreateWithName(it.font as CFString, it.size, nil)
                let color = CGColor(gray: it.gray, alpha: it.alpha)
                let attr = NSAttributedString(string: it.text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                ])
                let line = CTLineCreateWithAttributedString(attr)
                ctx.saveGState()
                ctx.translateBy(x: it.x, y: height - it.y - it.size * 0.8)
                ctx.rotate(by: it.angle * .pi / 180)
                ctx.textPosition = .zero
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}

/// Lays out screenplay elements like a script program does (Courier 12, fixed indents).
public struct FakeScript {
    public enum El { case scene(String), action(String), character(String), paren(String), dialogue(String), transition(String) }

    public struct Layout {
        var action: CGFloat = 108, character: CGFloat = 252, dialogue: CGFloat = 180, paren: CGFloat = 216
        var right: CGFloat = 540
        var actionChars = 60, dialogueChars = 35
        var width: CGFloat = 612, height: CGFloat = 792
        var top: CGFloat = 72, bottom: CGFloat = 720
        public static let finalDraft = Layout()
        /// A4, Word-like: smaller indents, wider text.
        public static let wordA4 = Layout(action: 70, character: 200, dialogue: 140, paren: 170, right: 525,
                                   actionChars: 66, dialogueChars: 40, width: 595, height: 842, top: 60, bottom: 780)
    }

    public var layout = Layout.finalDraft
    public var header: String? = nil            // repeated on every page (e.g. "CONFIDENTIAL – copy for …")
    public var pageNumbers = true
    public var sceneNumbers = false
    public var watermark: String? = nil         // diagonal, light grey, on every page
    public var titlePage: [String]? = nil
    public var more = ("(MORE)", "(CONT'D)")

    public init(layout: Layout = .finalDraft) { self.layout = layout }

    public func pdf(_ els: [El]) -> FakePDF {
        let L = layout, lh: CGFloat = 12
        var pdf = FakePDF(width: L.width, height: L.height)
        var page: [FakePDF.Item] = []
        var y = L.top
        var scene = 0
        var speaker: String?

        func finishPage() {
            let n = pdf.pages.count + 1
            if let header { page.append(.init(text: header, x: L.action, y: 30, size: 10)) }
            if pageNumbers && n > 1 { page.append(.init(text: "\(n).", x: L.right - 20, y: 40)) }
            if let watermark {
                page.append(.init(text: watermark, x: L.width * 0.2, y: L.height * 0.6, size: 48, font: "Helvetica-Bold",
                                  gray: 0.5, alpha: 0.25, angle: 45))
            }
            pdf.pages.append(page); page = []; y = L.top
        }
        func put(_ text: String, _ x: CGFloat) { page.append(.init(text: text, x: x, y: y)); y += lh }
        func wrap(_ s: String, _ n: Int) -> [String] {
            var lines: [String] = [], cur = ""
            for w in s.split(separator: " ") {
                if cur.isEmpty { cur = String(w) } else if cur.count + 1 + w.count <= n { cur += " " + w } else { lines.append(cur); cur = String(w) }
            }
            if !cur.isEmpty { lines.append(cur) }
            return lines
        }

        if let titlePage {
            y = L.height / 3
            for t in titlePage { let w = CGFloat(t.count) * 7.2; put(t, (L.width - w) / 2); y += lh }
            finishPage()
        }

        for el in els {
            switch el {
            case .scene(let s):
                y += lh; if y > L.bottom - 3 * lh { finishPage() }
                scene += 1
                if sceneNumbers { page.append(.init(text: "\(scene)", x: L.action - 40, y: y)); page.append(.init(text: "\(scene)", x: L.right + 10, y: y)) }
                put(s.uppercased(), L.action); y += lh; speaker = nil
            case .action(let s):
                for l in wrap(s, L.actionChars) { if y > L.bottom { finishPage() }; put(l, L.action) }
                y += lh; speaker = nil
            case .character(let s):
                if y > L.bottom - 2 * lh { finishPage() }
                put(s.uppercased(), L.character); speaker = s.uppercased()
            case .paren(let s):
                for l in wrap("(" + s + ")", L.dialogueChars - 10) { put(l, L.paren) }
            case .dialogue(let s):
                for l in wrap(s, L.dialogueChars) {
                    if y > L.bottom {
                        put(more.0, L.character); finishPage()
                        if let speaker { put("\(speaker) \(more.1)", L.character) }
                    }
                    put(l, L.dialogue)
                }
                y += lh
            case .transition(let s):
                let w = CGFloat(s.count) * 7.2
                put(s.uppercased(), L.right - w); y += lh
            }
        }
        if !page.isEmpty { finishPage() }
        return pdf
    }
}
