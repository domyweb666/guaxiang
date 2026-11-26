import XCTest
@testable import Guaxiang

/// 問古書的題數：沒付費 5 題，買了完整版再加 10 題（多米 2026-11-26）
final class PaywallTests: XCTestCase {
    func testFreeUsersGetFiveQuestions() {
        XCTAssertEqual(Paywall.allowance(purchased: false), 5)
        XCTAssertEqual(Paywall.left(asked: 0, purchased: false), 5)
        XCTAssertEqual(Paywall.left(asked: 4, purchased: false), 1)
        XCTAssertEqual(Paywall.left(asked: 5, purchased: false), 0)
    }

    func testPurchaseAddsTenOnTopOfFree() {
        XCTAssertEqual(Paywall.allowance(purchased: true), 15)
        // 免費的問完了才買，還有 10 題
        XCTAssertEqual(Paywall.left(asked: 5, purchased: true), 10)
    }

    func testLeftNeverGoesNegative() {
        XCTAssertEqual(Paywall.left(asked: 99, purchased: false), 0)
        XCTAssertEqual(Paywall.left(asked: 99, purchased: true), 0)
    }

    func testOutOfQuestionsHasNoPrice() {
        XCTAssertFalse(Paywall.outOfQuestions.contains("$"))
        XCTAssertFalse(Paywall.outOfQuestions.contains("元"))
    }
}
