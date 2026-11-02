// Declarations the QuartzCore Swift overlay needs, written for Darling from Core Animation's public API
// documentation. Darling's QuartzCore has no Clang module, so the overlay imports these instead of
// <QuartzCore/QuartzCore.h>.
#ifndef DARLING_QUARTZCORE_SHIMS_H
#define DARLING_QUARTZCORE_SHIMS_H

// CABase.h's frame rate range (macOS 12); Darling's QuartzCore headers predate it. The three-float layout is
// ABI: callers built against the macOS SDK pass and return this by value. The Clang importer mangles it as
// `So16CAFrameRateRangeV`, which is what apps built against the macOS SDK import.
typedef struct CAFrameRateRange {
	float minimum;
	float maximum;
	float preferred;
} CAFrameRateRange;

#endif
