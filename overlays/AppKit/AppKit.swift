// Minimal AppKit Swift overlay for Darling, written from AppKit's public Swift API documentation. It provides the
// AppKit Swift symbols that several macOS 26 apps import; everything else in AppKit is Objective-C and needs no
// overlay.

@_exported import Foundation
import CoreGraphics
// Re-export the AppKit Clang module where the SDK provides one. Without the re-export a Swift
// module named AppKit shadows the Clang module of the same name and every Objective-C type behind
// it becomes unreachable from Swift, even though Darling's headers declare them all.
//
// Gated on a build flag rather than on canImport(AppKit): inside the module being built as AppKit,
// canImport(AppKit) is true whether or not the Clang module exists, so it cannot discriminate.
// build.sh sets the flag when the SDK actually carries the module map.
#if DARLING_APPKIT_CLANG_MODULE
@_exported import AppKit
#else
import _DarlingAppKitShims
#endif

/// Runs the application's AppKit event loop using the supplied process arguments.
public func NSApplicationMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32 {
    let cArgv = UnsafeMutableRawPointer(argv)
        .assumingMemoryBound(to: UnsafePointer<CChar>?.self)
    // The type picks the C function over this overload; a module qualifier can't, since with the Clang module it is AppKit too.
    let cMain: (Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>) -> Int32 = NSApplicationMain
    return cMain(argc, cArgv)
}

extension CGRect {
    /// Fills the rectangle with the current fill color using the given compositing operation.
    public func fill(using operation: NSCompositingOperation) {
        NSRectFillUsingOperation(self, operation)
    }

    /// Draws a frame of the given width around the inside of the rectangle using the given compositing operation.
    public func frame(withWidth width: CGFloat, using operation: NSCompositingOperation) {
        NSFrameRectWithWidthUsingOperation(self, width, operation)
    }
}

extension NSSound {
    /// Plays the system beep.
    public static func beep() {
        NSBeep()
    }
}

extension NSImage {
    /// The image named `name`, as an image literal gives it; the image must exist.
    public convenience init(imageLiteralResourceName name: String) {
        self.init(named: name)!
    }
}
