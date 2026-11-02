// Minimal QuartzCore Swift overlay for Darling, written from Core Animation's public Swift API documentation. It
// provides the one QuartzCore Swift symbol apps import that the vendored 5.2.2 x86_64 slice predates; the rest of
// Core Animation is Objective-C and needs no overlay.

// Re-export the QuartzCore Clang module where the SDK provides one. Without the re-export a Swift
// module named QuartzCore shadows the Clang module of the same name and every Objective-C type behind
// it becomes unreachable from Swift, even though Darling's headers declare them all.
//
// Gated on a build flag rather than on canImport(QuartzCore): inside the module being built as QuartzCore,
// canImport(QuartzCore) is true whether or not the Clang module exists, so it cannot discriminate.
// build.sh sets the flag when the SDK actually carries the module map.
#if DARLING_QUARTZCORE_CLANG_MODULE
@_exported import QuartzCore
#else
// Without the Clang module, CAFrameRateRange comes from the private shim. Importing the shim alongside the Clang
// module would make every client of this overlay need the shim's module map.
import _DarlingQuartzCoreShims
#endif

extension CAFrameRateRange {
    /// A frame rate range with the given bounds, in frames per second.
    ///
    /// `preferred` is the frame rate Core Animation should aim for within the range; `nil` means no preference,
    /// which `CAFrameRateRangeMake` spells as `0`.
    public init(minimum: Float, maximum: Float, preferred: Float?) {
        self.init()
        self.minimum = minimum
        self.maximum = maximum
        self.preferred = preferred ?? 0
    }
}
