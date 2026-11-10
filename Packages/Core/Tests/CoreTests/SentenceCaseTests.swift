import Core
import Testing

struct SentenceCaseTests {
    @Test
    func capitalizesOnlyTheFirstLetter() {
        #expect("noviembre de 2026".sentenceCased == "Noviembre de 2026")
        #expect("November 2026".sentenceCased == "November 2026")
        #expect("".sentenceCased.isEmpty)
    }
}
