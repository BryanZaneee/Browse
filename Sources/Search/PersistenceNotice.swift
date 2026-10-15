import AppKit

@MainActor
enum PersistenceNotice {
    private static var shown: Set<UUID> = []
    private static var presenting = false

    static func alert(for issues: [Disk.Issue], quitting: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let unsaved = issues.contains { $0.kind != .recovered }
        alert.messageText = quitting ? "Quit with unsaved changes?" : (unsaved ? "Browse couldn’t save your data" : "Browse recovered unreadable data")
        let files = issues.prefix(3).map { $0.file.lastPathComponent }.joined(separator: ", ")
        let remainder = issues.count > 3 ? " and other files" : ""
        if quitting {
            alert.informativeText = "Changes to \(files)\(remainder) could not be saved. Keep Browse open to protect your current work, or quit and lose those changes."
            alert.addButton(withTitle: "Keep Working")
            alert.addButton(withTitle: "Quit Anyway")
        } else {
            let blocked = issues.contains { $0.kind == .read || $0.kind == .recovery }
            alert.informativeText = "Affected: \(files)\(remainder). " + (blocked
                ? "The original files are untouched. Saving to them is paused until you fix access and restart Browse. Keep this window open to protect current changes."
                : unsaved ? "Your changes remain in memory. Check free space and folder permissions, then try saving again. Browse will retry before quitting."
                : "The original bytes were moved to uniquely named unreadable files in the data folder. Keep those files if you need to recover saved items.")
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show Data Folder")
        }
        return alert
    }

    static func showPending() {
        guard !presenting, NSApp != nil, NSApp.activationPolicy() != .prohibited,
              !Browsers.quitting else { return }
        let issues = Disk.issues.filter { !shown.contains($0.id) }
        guard !issues.isEmpty else { return }
        shown.formUnion(issues.map(\.id))
        presenting = true
        let response = alert(for: issues, quitting: false).runModal()
        presenting = false
        DispatchQueue.main.async { showPending() }
        if response == .alertSecondButtonReturn { NSWorkspace.shared.open(Store.folder) }
    }

    static func confirmQuit() -> Bool {
        guard !presenting else { return false }
        let issues = Disk.issues.filter { $0.kind != .recovered }
        shown.formUnion(issues.map(\.id))
        presenting = true
        defer { presenting = false }
        return alert(for: issues, quitting: true).runModal() == .alertSecondButtonReturn
    }
}
