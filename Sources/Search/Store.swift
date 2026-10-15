import Foundation
import WebKit

// Where everything this browser keeps is kept.
//
// One place, and one rule: a run started for testing never touches the folder
// or the settings of the browser somebody is actually using. Sharing them once
// cost a person their pinned tabs, which is not a mistake worth being able to
// make twice.

enum Store {
    /// Development copies and XCTest never inherit the installed browser's data.
    static let testing: Bool = {
        let test = ProcessInfo.processInfo.environment["SEARCH_PROBE"] != nil
            || Bundle.main.infoDictionary?["BrowseTestRoot"] != nil
            || (Bundle.main.executablePath.map { $0.contains("/.build/") || $0.contains("/build/") } ?? false)
            || NSClassFromString("XCTestCase") != nil
        if test { TestPasteboard.install() }
        return test
    }()

    private static let unitID = (ProcessInfo.processInfo.environment["BROWSE_UNIT_ID"].flatMap(UUID.init(uuidString:)) ?? UUID()).uuidString.lowercased()
    private static let unitWebsites: WKWebsiteDataStore = {
        // Resume-data behavior requires a persistent store, even in XCTest.
        let root = folder.deletingLastPathComponent()
        let owner = ["id": unitID, "bundle": Bundle.main.bundleIdentifier ?? "", "pid": String(getpid())]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: owner).write(to: root.appendingPathComponent("webkit-owner.json"), options: .atomic)
        } catch { fatalError("Cannot record XCTest WebKit ownership: \(error)") }
        return WKWebsiteDataStore(forIdentifier: UUID(uuidString: unitID)!)
    }()

    static let world: String? = testing
        ? (Bundle.main.infoDictionary?["BrowseTestWorld"] as? String ?? "unit-\(unitID)") : nil

    /// Only the launcher gives a bundle its own identity and records its resources.
    static let testRoot: URL? = {
        guard testing, let root = Bundle.main.infoDictionary?["BrowseTestRoot"] as? String,
              let identity = Bundle.main.bundleIdentifier,
              identity.hasPrefix("com.bryanzaneee.browse.test."),
              let data = try? Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("owner.json")),
              let owner = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              owner["bundle"] == identity, owner["root"] == root,
              owner["world"] == world,
              Bundle.main.bundleURL.resolvingSymlinksInPath() == URL(fileURLWithPath: root + "/Browse.app").resolvingSymlinksInPath()
        else { return nil }
        let url = URL(fileURLWithPath: root, isDirectory: true)
        // /tmp is a system symlink; no resource below its owned parent may redirect elsewhere.
        for path in [url.deletingLastPathComponent(), url, url.appendingPathComponent("data"), url.appendingPathComponent("owner.json")] {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
                  attrs[.type] as? FileAttributeType != .typeSymbolicLink,
                  attrs[.ownerAccountID] as? UInt32 == getuid() else { return nil }
        }
        return url
    }()

    /// A test run there to be weighed and timed rather than driven
    /// (SEARCH_MEASURE beside SEARCH_PROBE). It keeps what the shipped
    /// browser does where test runs otherwise differ — hidden pages slowed
    /// the way WebKit slows them, App Nap left to macOS — so what gets
    /// measured is what people get.
    static var measuring: Bool {
        testing && ProcessInfo.processInfo.environment["SEARCH_MEASURE"] != nil
    }

    /// Cookies, sign-ins, caches. WebKit keeps its default store per bundle,
    /// not per folder, so a test run got every site already signed in — and
    /// "sign out of everything" in a test run signed the real browser out.
    /// A test run gets a store of its own, under a fixed name so it persists
    /// between probes the way the real one does. Wiping the test store is
    /// then as safe as wiping its folder.
    static var websites: WKWebsiteDataStore {
        guard testing else { return .default() }
        return ownContainer ? .default() : unitWebsites
    }

    /// Settings › Privacy › Prevent cross-site tracking, turned off. WebKit's
    /// tracking prevention, as in Safari, clears what a site it has seen
    /// redirect you — a sign-in through Google or Apple, say — left in local
    /// storage once you haven't opened it for a week or a month of use, and a
    /// site it counts as a tracker loses its cookies too: you are signed out.
    /// Turned off, that stops, and so does the rest of it: a site framed in
    /// another gets its cookies again, so trackers can follow you across
    /// sites, as in Chrome. On unless turned off; until then its flag is not
    /// touched.
    @MainActor static var keepsSignIns = false {
        didSet {
            guard keepsSignIns != oldValue else { return }
            Spaces.everyStore.forEach(followSignIns)
        }
    }

    /// The switch through a name outside the public framework — Safari's
    /// "Prevent cross-site tracking" is the same one.
    @MainActor static func followSignIns(_ store: WKWebsiteDataStore) {
        let set = NSSelectorFromString("_setResourceLoadStatisticsEnabled:")
        guard store.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(store.method(for: set), to: Setter.self)(store, set, !keepsSignIns)
    }

    /// A test copy of the app under a bundle id of its own has a WebKit
    /// container of its own too, so it can use WebKit's default store and
    /// extension configuration — the ones the real browser uses, which
    /// differ from stores made by identifier in how long extension workers
    /// are let live.
    static var ownContainer: Bool { testRoot != nil }

    /// Test files are contained by the recorded world; installed data stays where it was.
    static let folder: URL = {
        if testing {
            let root = testRoot ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("browse-unit-\(unitID)")
            return root.appendingPathComponent("data", isDirectory: true)
        }
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Browse", isDirectory: true)
    }()

    static func file(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    /// A file that didn't decode is set aside rather than overwritten the
    /// next time something is saved over it — bookmarks, history and a
    /// session are the kind of thing nobody wants to lose to a bad read with
    /// no trace of what was there. Failing to move it is fine: the read
    /// already came back empty either way, and there's nothing further to
    /// do about a folder that won't take a rename.
    static func quarantine(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = file.deletingLastPathComponent()
            .appendingPathComponent("\(file.deletingPathExtension().lastPathComponent).unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: file, to: aside)
    }

    /// Settings live apart too: a test that changes what the tabs wear or
    /// where the tabs go must not change yours.
    static let settings: UserDefaults = {
        guard testing else {
            return .standard
        }
        if ownContainer { return .standard }
        // A unit-test process has no app bundle. Its suite is never a production domain.
        atexit {
            UserDefaults.standard.removePersistentDomain(forName: "com.bryanzaneee.browse.unit.\(Store.unitID)")
            let root = Store.folder.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("webkit-owner.json").path) {
                try? FileManager.default.removeItem(at: Store.folder)
            } else { try? FileManager.default.removeItem(at: root) }
        }
        return UserDefaults(suiteName: "com.bryanzaneee.browse.unit.\(unitID)")!

    }()

}

/// Files written in the background, one at a time and the newest last.
///
/// Each save used to go to a concurrent queue on its own: two saves of the
/// same file a moment apart could land in either order, and the session
/// written at quit could be overwritten by an older one still on its way —
/// yesterday's tabs coming back instead of today's. Here every write joins
/// one serial queue, and a write that a newer one of the same file has
/// overtaken is dropped, including when the newer one was written at once
/// on the way out.
enum Disk {
    private static let queue = DispatchQueue(label: "search.disk", qos: .utility)
    private static let lock = NSLock()
    /// The newest write asked for, by file.
    nonisolated(unsafe) private static var newest: [URL: Int] = [:]
    nonisolated(unsafe) private static var count = 0

    /// `encode` runs where the write does. `now` writes on the calling
    /// thread: quitting doesn't wait for a queue.
    static func write(_ file: URL, now: Bool = false, _ encode: @escaping @Sendable () -> Data?) {
        lock.lock()
        count += 1
        let turn = count
        newest[file] = turn
        lock.unlock()
        let put: @Sendable () -> Void = {
            guard let data = encode() else { return }
            lock.lock()
            defer { lock.unlock() }
            // Overtaken: something newer of this file was asked for since.
            guard newest[file] == turn else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        if now { put() } else { queue.async(execute: put) }
    }

    /// Everything asked for so far, written — for the way out.
    static func drain() {
        queue.sync {}
    }
}
