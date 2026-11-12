import Testing
@testable import HarvestKit

@Suite struct AppHelpTests {
    @Test func spotsQuestions() {
        #expect(AppHelp.isQuestion("how do I split an entry"))
        #expect(AppHelp.isQuestion("dark mode?"))
        #expect(!AppHelp.isQuestion("website"))
        #expect(!AppHelp.isQuestion("30m on website"))
        #expect(!AppHelp.isQuestion("I worked on Context all morning"))
    }

    @Test func findsTheRightAnswer() {
        #expect(AppHelp.answers(for: "how do I split an entry?").first?.id == "split")
        #expect(AppHelp.answers(for: "how do i merge duplicate entries").first?.id == "merge")
        #expect(AppHelp.answers(for: "where is dark mode").first?.id == "appearance")
        #expect(AppHelp.answers(for: "how do I undo").first?.id == "undo")
        #expect(AppHelp.answers(for: "how do I qwzx").isEmpty)
        #expect(AppHelp.answers(for: "how do I put recent and suggested side by side").first?.id == "sections")
        #expect(AppHelp.answers(for: "what does this code mean?").first?.id == "guide")
        #expect(AppHelp.answers(for: "how do I move time to another task").first?.id == "move")
        #expect(AppHelp.answers(for: "open harvest website").first?.id == "web")
    }
}
