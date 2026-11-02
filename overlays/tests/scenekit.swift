// The SceneKit overlay's vector and matrix conversions, under Darling.
// SCNBoundingVolume is not exercised: Darling's SceneKit is a set of class stubs and implements none of its methods.
import Foundation
import CoreGraphics
import SceneKit
import _DarlingSceneKitShims

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok:" : "FAIL:", label)
    if !condition { failures += 1 }
}
func close(_ a: Double, _ b: Double) -> Bool { return abs(a - b) < 1e-5 }

let fromCGFloat = SCNVector3(CGFloat(1.5), CGFloat(-2.5), CGFloat(3.5))
check(close(Double(fromCGFloat.x), 1.5) && close(Double(fromCGFloat.y), -2.5) && close(Double(fromCGFloat.z), 3.5),
      "SCNVector3(CGFloat, CGFloat, CGFloat)")
let fromInt = SCNVector3(1, -2, 3)
check(close(Double(fromInt.x), 1) && close(Double(fromInt.y), -2) && close(Double(fromInt.z), 3),
      "SCNVector3(Int, Int, Int)")
let fromFloat = SCNVector3(Float(0.5), Float(0.25), Float(-0.125))
check(close(Double(fromFloat.x), 0.5) && close(Double(fromFloat.z), -0.125), "SCNVector3(Float, Float, Float)")

let v4 = SCNVector4(CGFloat(1), CGFloat(2), CGFloat(3), CGFloat(4))
check(close(Double(v4.w), 4), "SCNVector4(CGFloat, CGFloat, CGFloat, CGFloat)")
let v4i = SCNVector4(4, 3, 2, 1)
check(close(Double(v4i.x), 4) && close(Double(v4i.w), 1), "SCNVector4(Int, Int, Int, Int)")

let simd3 = SIMD3<Float>(fromCGFloat)
check(simd3.x == 1.5 && simd3.y == -2.5 && simd3.z == 3.5, "SIMD3<Float>(SCNVector3)")
check(SIMD3<Double>(fromCGFloat).y == -2.5, "SIMD3<Double>(SCNVector3)")
check(SIMD4<Float>(v4).w == 4, "SIMD4<Float>(SCNVector4)")
check(SCNVector3(simd3).y == fromCGFloat.y, "SCNVector3(SIMD3<Float>) round trip")

// Column-major: columns.N of the matrix is row N of CATransform3D (mN1...mN4).
let matrix = simd_float4x4(columns: (SIMD4<Float>(1, 2, 3, 4), SIMD4<Float>(5, 6, 7, 8),
                                     SIMD4<Float>(9, 10, 11, 12), SIMD4<Float>(13, 14, 15, 16)))
let transform = CATransform3D(matrix)
check(close(Double(transform.m11), 1) && close(Double(transform.m14), 4) &&
      close(Double(transform.m21), 5) && close(Double(transform.m41), 13) && close(Double(transform.m44), 16),
      "CATransform3D(simd_float4x4)")
let back = simd_float4x4(transform)
check(back.columns.0 == matrix.columns.0 && back.columns.3 == matrix.columns.3,
      "simd_float4x4(CATransform3D) round trip")
let doubleTransform = CATransform3D(simd_double4x4(transform))
check(close(Double(doubleTransform.m32), 10), "CATransform3D(simd_double4x4)")

print(failures == 0 ? "PASS" : "FAIL (\(failures))")
exit(failures == 0 ? 0 : 1)
