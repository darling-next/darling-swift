import AppKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

// Built with no private module map: `import AppKit` is the overlay plus the SDK's Clang module.
let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 10))
check(view.frame.width == 20, "NSView from the Clang module \(view.frame)")
check(NSLayoutConstraint.Priority.required.rawValue == 1000, "NSLayoutConstraint.Priority")
// The Swift-typed overload that `NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)` resolves to.
let main: (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 = NSApplicationMain
check(NSStringFromClass(NSView.self) == "NSView", "NSView class name")
_ = main

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
