import AppKit
import ObjectiveC

/// WebKit's UI process uses the named factory, including for DOM clipboard APIs.
/// Like WebKitTestRunner's mac pasteboard substitution, redirect it before views exist.
enum TestPasteboard {
    static func install() {
        let selector = NSSelectorFromString("_pasteboardWithName:")
        guard let method = class_getClassMethod(NSPasteboard.self, selector) else {
            fatalError("This macOS cannot isolate test clipboard access")
        }
        typealias Factory = @convention(c) (AnyClass, Selector, NSString?) -> NSPasteboard
        let original = unsafeBitCast(method_getImplementation(method), to: Factory.self)
        let prefix = "org.browse.test.\(UUID().uuidString)."
        let replacement: @convention(block) (AnyClass, NSString?) -> NSPasteboard = { cls, name in
            original(cls, selector, (prefix + ((name as String?) ?? UUID().uuidString)) as NSString)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}
