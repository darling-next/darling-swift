// Built without the _DarlingQuartzCoreShims module map: the overlay must re-export the QuartzCore Clang module
// and take CAFrameRateRange from it.
import QuartzCore

let layer = CALayer()
layer.bounds = CGRect(x: 0, y: 0, width: 8, height: 4)
CATransaction.begin()
layer.opacity = 0.5
CATransaction.commit()
let range = CAFrameRateRange(minimum: 30, maximum: 120, preferred: nil)
if layer.bounds.size.width == 8 && layer.opacity == 0.5 && range.minimum == 30 && range.maximum == 120
    && range.preferred == 0 && MemoryLayout<CAFrameRateRange>.size == 12 {
    print("ALL PASSED")
} else {
    print("FAIL: \(layer.bounds) \(layer.opacity) \(range)")
    exit(1)
}
