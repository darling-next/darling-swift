// Declarations the SceneKit Swift overlay needs, written for Darling from SceneKit's, QuartzCore's and simd's public
// API documentation. Darling's SceneKit headers are a reverse-engineered dump of the framework's internal classes:
// they declare neither SCNVector3/SCNVector4 nor the SCNBoundingVolume methods, and Darling's SDK ships no QuartzCore
// or simd module, so the overlay imports these instead.
//
// Tag naming is load-bearing. A named tag (`struct SCNVector3`) is imported as a Swift struct and mangles
// `So10SCNVector3V`; a typedef of an anonymous struct mangles as a typealias, `So13simd_float4x4a`. Both forms appear
// in the symbols apps built against the macOS SDK import, so each type here uses the form Apple's headers use.
#ifndef DARLING_SCENEKIT_SHIMS_H
#define DARLING_SCENEKIT_SHIMS_H

#import <Foundation/Foundation.h>

// MARK: - simd (simd/vector_types.h, simd/matrix_types.h)

typedef float simd_float1;
typedef double simd_double1;
typedef simd_float1 simd_float4 __attribute__((ext_vector_type(4)));
typedef simd_double1 simd_double4 __attribute__((ext_vector_type(4)));

typedef struct { simd_float4 columns[4]; } simd_float4x4;
typedef struct { simd_double4 columns[4]; } simd_double4x4;

// MARK: - QuartzCore (QuartzCore/CATransform3D.h)

struct CATransform3D {
	CGFloat m11, m12, m13, m14;
	CGFloat m21, m22, m23, m24;
	CGFloat m31, m32, m33, m34;
	CGFloat m41, m42, m43, m44;
};
typedef struct CATransform3D CATransform3D;

// MARK: - SceneKit (SceneKit/SceneKitTypes.h)

typedef CGFloat SCNFloat;

typedef struct SCNVector3 {
	SCNFloat x, y, z;
} SCNVector3;

typedef struct SCNVector4 {
	SCNFloat x, y, z, w;
} SCNVector4;

@protocol SCNBoundingVolume <NSObject>
- (BOOL)getBoundingBoxMin:(nullable SCNVector3 *)min max:(nullable SCNVector3 *)max;
- (BOOL)getBoundingSphereCenter:(nullable SCNVector3 *)center radius:(nullable CGFloat *)radius;
- (void)setBoundingBoxMin:(nullable SCNVector3 *)min max:(nullable SCNVector3 *)max;
@end

#endif
