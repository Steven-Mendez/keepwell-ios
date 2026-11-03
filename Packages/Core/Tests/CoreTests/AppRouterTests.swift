import Testing
@testable import Core

@Suite("AppRouter")
@MainActor
struct AppRouterTests {
    @Test
    func pushAndPop() {
        let router = AppRouter()
        router.push(.addTransaction)
        #expect(router.path.count == 1)
        router.pop()
        #expect(router.path.isEmpty)
    }

    @Test
    func popOnEmptyPathIsNoOp() {
        let router = AppRouter()
        router.pop()
        #expect(router.path.isEmpty)
    }
}
