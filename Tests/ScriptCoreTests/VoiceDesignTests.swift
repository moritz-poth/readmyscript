import Foundation
import Testing
@testable import ScriptCore

struct VoiceDesignTests {
    @Test func tagsAreVoiceStudios() throws {
        var d = VoiceDesign()
        d.gender = .female; d.age = .youngAdult; d.pitch = .veryLow; d.whisper = true
        #expect(d.instruct == "female, young adult, very low pitch, whisper")
        let s = try JSONSerialization.jsonObject(with: Data(d.states.utf8)) as? [String: String]
        #expect(s == ["Gender": "female", "Age": "young adult", "Pitch": "very low pitch", "Style": "whisper"])
        d.whisper = false
        #expect(d.instruct == "female, young adult, very low pitch")
        #expect(d.states.contains(#""Style":"Auto""#))
    }
}
