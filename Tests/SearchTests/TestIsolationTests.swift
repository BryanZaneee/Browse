import AppKit
import XCTest
@testable import Search

final class TestIsolationTests: XCTestCase {
    func testCredentialsAndConsentStayInProcess() {
        XCTAssertTrue(Store.testing)
        let host = "isolation.example.test"
        XCTAssertTrue(Vault.save(host: host, user: "fixture", password: "synthetic-a"))
        XCTAssertEqual(Vault.logins(for: host).first?.password, "synthetic-a")
        XCTAssertTrue(Vault.save(host: host, user: "fixture", password: "synthetic-b"))
        XCTAssertEqual(Vault.logins(for: host).count, 1)
        XCTAssertEqual(Vault.logins(for: host).first?.password, "synthetic-b")
        Vault.forget(host: host, user: "fixture")
        XCTAssertTrue(Vault.logins(for: host).isEmpty)
    }

    @MainActor func testNativeClipboardUsesOwnedBoard() {
        XCTAssertTrue(Store.testing)
        let board = NSPasteboard.general
        XCTAssertTrue(board.name.rawValue.hasPrefix("org.browse.test."))
        XCTAssertEqual(NSPasteboard(name: .general).name, board.name)
        let view = NSTextView(frame: .zero)
        view.string = "synthetic clipboard"
        view.selectAll(nil)
        view.cut(nil)
        XCTAssertEqual(view.string, "")
        view.paste(nil)
        XCTAssertEqual(view.string, "synthetic clipboard")
        board.clearContents()
    }

    @MainActor func testUnitWebKitOwnsAPersistentIdentifier() {
        XCTAssertFalse(Store.ownContainer)
        XCTAssertTrue(Store.websites.isPersistent)
        XCTAssertNotNil(Store.websites.identifier)
        XCTAssertTrue(Store.websites === Store.websites)
        Bench.Consent.grant()
        XCTAssertTrue(Bench.Consent.given)
        Bench.Consent.revoke()
        XCTAssertFalse(Bench.Consent.given)
    }
}
