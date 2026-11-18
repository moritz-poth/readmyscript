import Foundation

/// A small invented screenplay for the self-test: two layouts (Final Draft / Word A4), a watermark, page headers.
/// Neutral text only – the self-test never touches the user's scripts.
public enum DemoScript {
    public static let scenes = 2
    public static let roles = ["ANNA", "BEN"]

    static let elements: [FakeScript.El] = [
        .scene("INT. KITCHEN - NIGHT"),
        .action("ANNA sits at the table. The kettle starts to whistle."),
        .character("Anna"),
        .dialogue("You are late again."),
        .character("Ben"),
        .paren("quietly"),
        .dialogue("The train stopped twice. I am sorry."),
        .transition("CUT TO:"),
        .scene("EXT. STREET - DAY"),
        .action("Rain. Ben runs for the bus."),
        .character("Anna"),
        .dialogue("Wait for me!"),
    ]

    /// Writes both test PDFs into `dir` and returns their URLs.
    public static func write(to dir: URL) -> [URL] {
        var finalDraft = FakeScript()
        finalDraft.header = "DEMO SCRIPT – SELF-TEST"
        finalDraft.watermark = "SELF-TEST"
        finalDraft.sceneNumbers = true
        var wordA4 = FakeScript()
        wordA4.layout = .wordA4
        let a = dir.appendingPathComponent("demo-final-draft.pdf"), b = dir.appendingPathComponent("demo-a4.pdf")
        finalDraft.pdf(elements).write(to: a)
        wordA4.pdf(elements).write(to: b)
        return [a, b]
    }
}
