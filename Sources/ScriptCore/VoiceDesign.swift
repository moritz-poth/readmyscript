import Foundation

/// A voice VoiceStudio builds from attributes (its "Voice Design"), no reference recording needed.
/// The seed fixes which of the many voices with these attributes you get.
public struct VoiceDesign: Equatable, Sendable {
    // Values are VoiceStudio's own tags (backend/core/describe_voice.py).
    public enum Gender: String, CaseIterable, Sendable { case male, female }
    public enum Age: String, CaseIterable, Sendable {
        case child, teenager, youngAdult = "young adult", middleAged = "middle-aged", elderly
    }
    public enum Pitch: String, CaseIterable, Sendable {
        case veryLow = "very low pitch", low = "low pitch", moderate = "moderate pitch", high = "high pitch", veryHigh = "very high pitch"
    }

    public var gender: Gender = .male
    public var age: Age = .middleAged
    public var pitch: Pitch = .moderate
    public var whisper = false
    public var seed = Int.random(in: 1...99_999)

    public init() {}

    /// "male, middle-aged, moderate pitch"
    public var instruct: String {
        ([gender.rawValue, age.rawValue, pitch.rawValue] + (whisper ? ["whisper"] : [])).joined(separator: ", ")
    }

    /// The picker state VoiceStudio stores with a design profile (JSON object, one key per category).
    public var states: String {
        let s = ["Gender": gender.rawValue, "Age": age.rawValue, "Pitch": pitch.rawValue, "Style": whisper ? "whisper" : "Auto"]
        return String(data: try! JSONSerialization.data(withJSONObject: s, options: .sortedKeys), encoding: .utf8)!
    }
}
