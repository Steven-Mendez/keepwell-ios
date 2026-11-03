import Testing
@testable import Core

@Suite("AppRouter")
@MainActor
struct AppRouterTests {
    @Test
    func popOnEmptyPathIsNoOp() {
        let router = AppRouter()
        router.pop()
        #expect(router.path.isEmpty)
    }
}
