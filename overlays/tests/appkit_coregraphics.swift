// CGContext.addLine(to:)/addArc(center:...) through the CoreGraphics overlay and NSImage(imageLiteralResourceName:)
// through the AppKit overlay, under Darling. Build with -import-objc-header tests/appkit_coregraphics.h.
import AppKit
import CoreGraphics
import _DarlingAppKitShims

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok:" : "FAIL:", label)
    if !condition { failures += 1 }
}
func close(_ a: CGFloat, _ b: CGFloat) -> Bool { return abs(a - b) < 0.5 }

// kCGImageAlphaPremultipliedLast
let premultipliedLast: UInt32 = 1
if let context = CGBitmapContextCreate(nil, 64, 64, 8, 256, CGColorSpaceCreateDeviceRGB(), premultipliedLast) {
    CGContextBeginPath(context)
    CGContextMoveToPoint(context, 1, 2)
    context.addLine(to: CGPoint(x: 10, y: 20))
    let point = CGContextGetPathCurrentPoint(context)
    check(close(point.x, 10) && close(point.y, 20), "addLine(to:) moves the current point (\(point.x), \(point.y))")
    let line = CGContextGetPathBoundingBox(context)
    check(close(line.origin.x, 1) && close(line.origin.y, 2) && close(line.size.width, 9) && close(line.size.height, 18),
          "addLine(to:) adds the segment (\(line))")

    // A quarter circle counterclockwise from angle 0 stays in the upper right quadrant.
    CGContextBeginPath(context)
    CGContextMoveToPoint(context, 40, 30)
    context.addArc(center: CGPoint(x: 30, y: 30), radius: 10, startAngle: 0, endAngle: .pi / 2, clockwise: false)
    let end = CGContextGetPathCurrentPoint(context)
    check(close(end.x, 30) && close(end.y, 40), "addArc ends at endAngle (\(end.x), \(end.y))")
    let quarter = CGContextGetPathBoundingBox(context)
    check(close(quarter.origin.x, 30) && close(quarter.origin.y, 30) && close(quarter.size.width, 10)
          && close(quarter.size.height, 10), "addArc counterclockwise sweeps a quarter (\(quarter))")

    // Clockwise from 0 to pi/2 sweeps the other three quarters.
    CGContextBeginPath(context)
    CGContextMoveToPoint(context, 40, 30)
    context.addArc(center: CGPoint(x: 30, y: 30), radius: 10, startAngle: 0, endAngle: .pi / 2, clockwise: true)
    let threeQuarters = CGContextGetPathBoundingBox(context)
    check(close(threeQuarters.origin.x, 20) && close(threeQuarters.origin.y, 20) && close(threeQuarters.size.width, 20)
          && close(threeQuarters.size.height, 20), "addArc clockwise sweeps three quarters (\(threeQuarters))")
} else {
    check(false, "CGBitmapContextCreate")
}

// NSImage(imageLiteralResourceName:) returns the image registered under that name.
let image = NSImage()
_ = image.perform(Selector(("setName:")), with: "DarlingBootCampImage")
let named = NSImage(imageLiteralResourceName: "DarlingBootCampImage")
check(named === image, "NSImage(imageLiteralResourceName:) finds a named image")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
