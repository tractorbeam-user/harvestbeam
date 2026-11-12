import Testing
@testable import HarvestKit

struct DescribesWorkTests {
    @Test(arguments: [
        "i did the LP site and a client call",
        "I worked on Context design all morning",
        "spent an hour on the website",
        "today i had a call with Dallas Art Fair",
        "context design then admin then a call with the LP team",
        "LP site 2h, client call 30m",
    ])
    func sentencesAboutTheDay(_ text: String) {
        #expect(DayPlanner.describesWork(text))
    }

    @Test(arguments: [
        "research", "dallas art fair", "tb corporate", "managerial tasks",
        "10 min on tb corporate", "LP site 2h", "",
    ])
    func searchesStaySearches(_ text: String) {
        #expect(!DayPlanner.describesWork(text))
    }
}
