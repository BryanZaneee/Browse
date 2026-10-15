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
    struct Issue: Equatable {
        enum Kind { case read, recovery, save, recovered }
        let id = UUID()
        let file: URL
        let kind: Kind
        var backup: URL? = nil
    }
    private struct Request {
        let turn: Int
        let encode: @Sendable () throws -> Data
    }
    static let changed = Notification.Name("BrowseDiskIssuesChanged")
    private static let queue = DispatchQueue(label: "search.disk", qos: .utility)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var newest: [URL: Int] = [:]
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var failures: [URL: Issue] = [:]
    nonisolated(unsafe) private static var pending: [URL: Request] = [:]
    nonisolated(unsafe) private static var blocked: Set<URL> = []

    static var issues: [Issue] {
        lock.lock(); defer { lock.unlock() }
        return failures.values.sorted { $0.file.path < $1.file.path }
    }

    static var hasUnsavedChanges: Bool {
        lock.lock(); defer { lock.unlock() }
        return !pending.isEmpty || !blocked.isEmpty
    }

    // Called with the lock held. Notices never include encoded data or error contents.
    private static func report(_ issue: Issue) {
        if let previous = failures[issue.file], previous.kind == issue.kind, previous.backup == issue.backup { return }
        failures[issue.file] = issue
        DispatchQueue.main.async { NotificationCenter.default.post(name: changed, object: nil) }
    }

    /// Missing is a first run; unreadable is not. Never overwrite bytes we couldn't preserve.
    static func read<Value: Decodable>(_ type: Value.Type, from file: URL) -> Value? {
        lock.lock(); defer { lock.unlock() }
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        catch {
            blocked.insert(file)
            report(Issue(file: file, kind: .read))
            return nil
        }
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            let backup = file.deletingLastPathComponent().appendingPathComponent(
                "\(file.deletingPathExtension().lastPathComponent).unreadable-\(UUID().uuidString).json")
            do {
                try FileManager.default.moveItem(at: file, to: backup)
                report(Issue(file: file, kind: .recovered, backup: backup))
            } catch {
                blocked.insert(file)
                report(Issue(file: file, kind: .recovery))
            }
            return nil
        }
    }

    static func write(_ file: URL, now: Bool = false, _ encode: @escaping @Sendable () throws -> Data) {
        lock.lock()
        count += 1
        let request = Request(turn: count, encode: encode)
        newest[file] = count
        lock.unlock()
        if now { put(file, request) } else { queue.async { put(file, request) } }
    }

    private static func put(_ file: URL, _ request: Request) {
        // Encoding a snapshot may be expensive; don't hold the filesystem lock while doing it.
        let data = Result { try request.encode() }
        lock.lock(); defer { lock.unlock() }
        guard newest[file] == request.turn else { return }
        pending[file] = request
        guard !blocked.contains(file) else { return }
        do {
            let bytes = try data.get()
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: file, options: .atomic)
            pending.removeValue(forKey: file)
            if failures[file]?.kind == .save { failures.removeValue(forKey: file) }
        } catch { report(Issue(file: file, kind: .save)) }
    }

    /// Retry only the latest failed snapshot; a newer request still wins.
    static func retry() {
        drain()
        lock.lock()
        let requests = pending
        lock.unlock()
        for (file, request) in requests { put(file, request) }
    }

    static func drain() { queue.sync {} }

    /// Unit fixtures must not retain failed closures or blocks after their directory is removed.
    static func clearTestState(in folder: URL) {
        precondition(Store.testing)
        drain()
        lock.lock(); defer { lock.unlock() }
        for file in Set(failures.keys).union(pending.keys).union(newest.keys) where file.deletingLastPathComponent().path == folder.path {
            failures.removeValue(forKey: file)
            pending.removeValue(forKey: file)
            newest.removeValue(forKey: file)
            blocked.remove(file)
        }
    }
}
