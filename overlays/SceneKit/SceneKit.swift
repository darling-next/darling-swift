// SceneKit Swift overlay for Darling, written from SceneKit's public Swift API documentation and the symbol names
// apps import. Apple never open-sourced this overlay.
//
// Intentionally partial. It covers the conversions between SCNVector3/SCNVector4, the Swift SIMD types and CGFloat,
// the CATransform3D/simd matrix conversions, and SCNBoundingVolume's boundingBox and boundingSphere. It leaves out
// the _ObjectiveCBridgeable conformances of SCNVector3/SCNVector4 (NSValue has no +valueWithSCNVector3: in Darling),
// the SCNGeometrySource and SCNGeometryElement convenience initializers, and
// SCNSceneSource.entryWithIdentifier(_:withClass:): Darling's SceneKit is a set of class stubs whose whole Objective-C
// method-name section is 86 bytes, so there is nothing for those to call.

@_exported import Foundation
import CoreGraphics
import _DarlingSceneKitShims

// MARK: - SCNVector3

extension SCNVector3 {
	public init(_ x: Float, _ y: Float, _ z: Float) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
	}

	public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
	}

	public init(_ x: Double, _ y: Double, _ z: Double) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
	}

	public init(_ x: Int, _ y: Int, _ z: Int) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
	}

	public init(_ v: SIMD3<Float>) {
		self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z))
	}

	public init(_ v: SIMD3<Double>) {
		self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z))
	}
}

extension SIMD3 where Scalar == Float {
	public init(_ v: SCNVector3) {
		self.init(Float(v.x), Float(v.y), Float(v.z))
	}
}

extension SIMD3 where Scalar == Double {
	public init(_ v: SCNVector3) {
		self.init(Double(v.x), Double(v.y), Double(v.z))
	}
}

// MARK: - SCNVector4

extension SCNVector4 {
	public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
	}

	public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
	}

	public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
	}

	public init(_ x: Int, _ y: Int, _ z: Int, _ w: Int) {
		self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
	}

	public init(_ v: SIMD4<Float>) {
		self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z), w: SCNFloat(v.w))
	}

	public init(_ v: SIMD4<Double>) {
		self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z), w: SCNFloat(v.w))
	}
}

extension SIMD4 where Scalar == Float {
	public init(_ v: SCNVector4) {
		self.init(Float(v.x), Float(v.y), Float(v.z), Float(v.w))
	}
}

extension SIMD4 where Scalar == Double {
	public init(_ v: SCNVector4) {
		self.init(Double(v.x), Double(v.y), Double(v.z), Double(v.w))
	}
}

// MARK: - CATransform3D and the simd matrices
//
// Both are column-major: CATransform3D's mIJ is row I, column J, so column I is (m[I]1, m[I]2, m[I]3, m[I]4).

extension CATransform3D {
	public init(_ m: simd_float4x4) {
		self.init(
			m11: CGFloat(m.columns.0.x), m12: CGFloat(m.columns.0.y),
			m13: CGFloat(m.columns.0.z), m14: CGFloat(m.columns.0.w),
			m21: CGFloat(m.columns.1.x), m22: CGFloat(m.columns.1.y),
			m23: CGFloat(m.columns.1.z), m24: CGFloat(m.columns.1.w),
			m31: CGFloat(m.columns.2.x), m32: CGFloat(m.columns.2.y),
			m33: CGFloat(m.columns.2.z), m34: CGFloat(m.columns.2.w),
			m41: CGFloat(m.columns.3.x), m42: CGFloat(m.columns.3.y),
			m43: CGFloat(m.columns.3.z), m44: CGFloat(m.columns.3.w))
	}

	public init(_ m: simd_double4x4) {
		self.init(
			m11: CGFloat(m.columns.0.x), m12: CGFloat(m.columns.0.y),
			m13: CGFloat(m.columns.0.z), m14: CGFloat(m.columns.0.w),
			m21: CGFloat(m.columns.1.x), m22: CGFloat(m.columns.1.y),
			m23: CGFloat(m.columns.1.z), m24: CGFloat(m.columns.1.w),
			m31: CGFloat(m.columns.2.x), m32: CGFloat(m.columns.2.y),
			m33: CGFloat(m.columns.2.z), m34: CGFloat(m.columns.2.w),
			m41: CGFloat(m.columns.3.x), m42: CGFloat(m.columns.3.y),
			m43: CGFloat(m.columns.3.z), m44: CGFloat(m.columns.3.w))
	}
}

extension simd_float4x4 {
	public init(_ t: CATransform3D) {
		self.init(columns: (
			SIMD4<Float>(Float(t.m11), Float(t.m12), Float(t.m13), Float(t.m14)),
			SIMD4<Float>(Float(t.m21), Float(t.m22), Float(t.m23), Float(t.m24)),
			SIMD4<Float>(Float(t.m31), Float(t.m32), Float(t.m33), Float(t.m34)),
			SIMD4<Float>(Float(t.m41), Float(t.m42), Float(t.m43), Float(t.m44))))
	}
}

extension simd_double4x4 {
	public init(_ t: CATransform3D) {
		self.init(columns: (
			SIMD4<Double>(Double(t.m11), Double(t.m12), Double(t.m13), Double(t.m14)),
			SIMD4<Double>(Double(t.m21), Double(t.m22), Double(t.m23), Double(t.m24)),
			SIMD4<Double>(Double(t.m31), Double(t.m32), Double(t.m33), Double(t.m34)),
			SIMD4<Double>(Double(t.m41), Double(t.m42), Double(t.m43), Double(t.m44))))
	}
}

// MARK: - SCNBoundingVolume

extension SCNBoundingVolume {
	/// The minimum and maximum corners of the object's bounding box, in its local coordinate space.
	///
	/// The property cannot report failure, so an object without a bounding box reads as two zero vectors, the same
	/// as on macOS.
	public var boundingBox: (min: SCNVector3, max: SCNVector3) {
		get {
			var minimum = SCNVector3(x: 0, y: 0, z: 0)
			var maximum = SCNVector3(x: 0, y: 0, z: 0)
			_ = getBoundingBoxMin(&minimum, max: &maximum)
			return (minimum, maximum)
		}
		set {
			var minimum = newValue.min
			var maximum = newValue.max
			setBoundingBoxMin(&minimum, max: &maximum)
		}
	}

	/// The centre and radius of the object's bounding sphere, in its local coordinate space.
	public var boundingSphere: (center: SCNVector3, radius: Float) {
		var centre = SCNVector3(x: 0, y: 0, z: 0)
		var radius: CGFloat = 0
		_ = getBoundingSphereCenter(&centre, radius: &radius)
		return (centre, Float(radius))
	}
}
