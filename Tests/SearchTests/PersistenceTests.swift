import AppKit
import Darwin
import XCTest
@testable import Search

final class PersistenceTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("browse-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        Disk.clearTestState(in: folder)
        try FileManager.default.removeItem(at: folder)
    }
    private var file: URL { folder.appendingPathComponent("state.json") }
    private let original = Data("[\"kept\"]".utf8)

    func testMissingFileIsNotARecoveryFailure() {
        XCTAssertNil(Disk.read([String].self, from: file))
        XCTAssertFalse(Disk.issues.contains { $0.file == file })
    }

    func testMalformedDataIsPreservedUnderUniqueNamesBeforeSaving() throws {
        let corrupt = Data("{interrupted".utf8)
        for _ in 0..<2 {
            try corrupt.write(to: file)
            XCTAssertNil(Disk.read([String].self, from: file))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 2)
        for backup in backups { XCTAssertEqual(try Data(contentsOf: backup), corrupt) }
        let bytes = original
        Disk.write(file, now: true) { bytes }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(Disk.issues.first { $0.file == file }?.kind, .recovered)
    }

    func testFailedQuarantineBlocksLaterOverwriteEvenAfterAccessReturns() throws {
        let corrupt = Data("{recover me".utf8)
        try corrupt.write(to: file)
        XCTAssertEqual(chflags(file.path, UInt32(UF_IMMUTABLE)), 0)
        defer { _ = chflags(file.path, 0) }
        XCTAssertNil(Disk.read([String].self, from: file))
        XCTAssertEqual(Disk.issues.first { $0.file == file }?.kind, .recovery)
        XCTAssertEqual(chflags(file.path, 0), 0)
        let bytes = original
        Disk.write(file, now: true) { bytes }
        Disk.retry()
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testRecoveryAndLaterSaveFailureHaveDistinctNoticeIdentities() throws {
        try Data("{".utf8).write(to: file)
        XCTAssertNil(Disk.read([String].self, from: file))
        let recovered = try XCTUnwrap(Disk.issues.first { $0.file == file })
        enum Failure: Error { case encode }
        Disk.write(file, now: true) { throw Failure.encode }
        let failed = try XCTUnwrap(Disk.issues.first { $0.file == file })
        XCTAssertEqual(failed.kind, .save)
        XCTAssertNotEqual(failed.id, recovered.id)
        Disk.retry()
        XCTAssertEqual(Disk.issues.first { $0.file == file }?.id, failed.id, "Repeated failures should not flood notices")
        Disk.write(file, now: true) { Data("[]".utf8) }
        Disk.write(file, now: true) { throw Failure.encode }
        XCTAssertNotEqual(Disk.issues.first { $0.file == file }?.id, failed.id)
    }

    func testUnreadableDestinationIsNotTreatedAsAnEmptyFile() throws {
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let sentinel = file.appendingPathComponent("original")
        try original.write(to: sentinel)
        XCTAssertNil(Disk.read([String].self, from: file))
        XCTAssertEqual(Disk.issues.first { $0.file == file }?.kind, .read)
        Disk.write(file, now: true) { Data("[]".utf8) }
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
    }

    func testFailedAtomicReplacementPreservesBytesAndRetriesLatestSnapshot() throws {
        try original.write(to: file)
        XCTAssertEqual(chflags(file.path, UInt32(UF_IMMUTABLE)), 0)
        defer { _ = chflags(file.path, 0) }
        Disk.write(file, now: true) { Data("[\"old pending\"]".utf8) }
        Disk.write(file, now: true) { Data("[\"latest\"]".utf8) }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(Disk.issues.first { $0.file == file }?.kind, .save)
        XCTAssertEqual(chflags(file.path, 0), 0)
        Disk.retry()
        XCTAssertEqual(try Data(contentsOf: file), Data("[\"latest\"]".utf8))
        XCTAssertFalse(Disk.issues.contains { $0.file == file })
    }

    func testEncodingFailureDoesNotReplacePreviousFile() throws {
        enum Interrupted: Error { case encode }
        try original.write(to: file)
        Disk.write(file, now: true) { throw Interrupted.encode }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(Disk.issues.first { $0.file == file }?.kind, .save)
        let bytes = original
        Disk.write(file, now: true) { bytes }
        XCTAssertFalse(Disk.issues.contains { $0.file == file })
    }

    func testInterruptedOlderPreparationCannotOverwriteNewerSave() throws {
        let started = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        Disk.write(file) {
            started.signal()
            _ = finish.wait(timeout: .now() + 5)
            return Data("[\"older\"]".utf8)
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        Disk.write(file, now: true) { Data("[\"newer\"]".utf8) }
        finish.signal()
        Disk.drain()
        XCTAssertEqual(try Data(contentsOf: file), Data("[\"newer\"]".utf8))
    }

    @MainActor
    func testQuitWaitsForSaveAndKeepsWindowsAliveWhenUserCancels() throws {
        try original.write(to: file)
        XCTAssertEqual(chflags(file.path, UInt32(UF_IMMUTABLE)), 0)
        defer { _ = chflags(file.path, 0); Browsers.quitting = false }
        Disk.write(file) { Data("[\"pending\"]".utf8) }
        Browsers.quitting = true
        var asked = false
        XCTAssertEqual(Links.saveBeforeQuit { asked = true; return false }, .terminateCancel)
        XCTAssertTrue(asked)
        XCTAssertFalse(Browsers.quitting)
        XCTAssertEqual(try Data(contentsOf: file), original)
        Browsers.quitting = true
        XCTAssertEqual(Links.saveBeforeQuit { true }, .terminateNow)
        XCTAssertEqual(chflags(file.path, 0), 0)
        XCTAssertEqual(Links.saveBeforeQuit { XCTFail("successful retry should not ask"); return false }, .terminateNow)
        XCTAssertEqual(try Data(contentsOf: file), Data("[\"pending\"]".utf8))
    }

    @MainActor
    func testQuitNoticeDefaultsToKeepingWorkAndNeverIncludesContents() {
        _ = NSApplication.shared
        let alert = PersistenceNotice.alert(for: [Disk.Issue(file: file, kind: .save)], quitting: true)
        XCTAssertEqual(alert.buttons.map(\.title), ["Keep Working", "Quit Anyway"])
        XCTAssertEqual(alert.buttons.first?.keyEquivalent, "\r")
        XCTAssertTrue(alert.informativeText.contains("state.json"))
        XCTAssertFalse(alert.informativeText.contains(folder.path))
    }
    @MainActor
    func testCapturePersistenceNotices() throws {
        guard let path = ProcessInfo.processInfo.environment["BROWSE_PERSISTENCE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Opt-in fixture: Tests/PersistenceFixture/run.sh")
        }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for (name, kind, quitting) in [("save", Disk.Issue.Kind.save, false), ("recovery", .recovered, false), ("quit", .save, true)] {
                let issue = Disk.Issue(file: URL(fileURLWithPath: "/fixture/windows.json"), kind: kind)
                let alert = PersistenceNotice.alert(for: [issue], quitting: quitting)
                let window = alert.window
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                alert.layout()
                window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
                window.orderFront(nil)
                defer { window.orderOut(nil) }
                let view = try XCTUnwrap(window.contentView)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let image = NSImage(size: view.bounds.size)
                NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                    image.lockFocus()
                    NSColor.windowBackgroundColor.setFill()
                    view.bounds.fill()
                    let foreground = NSImage(size: view.bounds.size)
                    foreground.addRepresentation(bitmap)
                    foreground.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1)
                    image.unlockFocus()
                }
                let rendered = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                let data = try XCTUnwrap(rendered.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("persistence-\(name)-\(dark ? "dark" : "light").png"))

            }
        }
    }

}
