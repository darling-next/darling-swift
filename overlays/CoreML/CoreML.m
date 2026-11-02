/*
 * CoreML.framework -- a TRUTHFUL substitute for Apple's /System/Library/Frameworks/CoreML.framework.
 *
 * WHY IT EXISTS. The Xcode 26.3 load-time ladder reaches this image through DVTSmartSearch:
 *
 *   Library not loaded: /System/Library/Frameworks/CoreML.framework/Versions/A/CoreML
 *   Referenced from: .../Xcode.app/Contents/SharedFrameworks/DVTSmartSearch.framework/Versions/A/DVTSmartSearch
 *
 * DVTSmartSearch is the ONE referrer and it links the image STRONGLY (LC_LOAD_DYLIB, compatibility
 * 1.0.0). It binds SIX names from the dependency field `CoreML`, all classrefs, measured per
 * dependency field with `llvm-objdump --macho --dyld-info`:
 *
 *   _OBJC_CLASS_$_MLFeatureDescription, _OBJC_CLASS_$_MLFeatureValue, _OBJC_CLASS_$_MLModel,
 *   _OBJC_CLASS_$_MLModelConfiguration, _OBJC_CLASS_$_MLMultiArray, _OBJC_CLASS_$_MLPredictionOptions
 *
 * SHAPES. Apple ships both the headers and a stub for this framework, and they are the source of
 * every signature below (nothing here is invented):
 *   <Xcode>/.../MacOSX.sdk/System/Library/Frameworks/CoreML.framework/Headers (every header)
 *   <Xcode>/.../MacOSX.sdk/System/Library/Frameworks/CoreML.framework/CoreML.tbd
 * The six classes are the whole DEMAND, but a classref is not a contract -- what the client SENDS
 * the classes is, so the reachable selectors were read out of DVTSmartSearch's own image (its
 * __objc_methname strings, each one confirmed against the SDK header that declares it):
 *
 *   +[MLModel modelWithContentsOfURL:configuration:error:]   (MLModel.h:44)
 *   +[MLModel compileModelAtURL:error:]                      (MLModel+MLModelCompilation.h:35)
 *   -[MLModel predictionFromFeatures:options:error:]          (MLModel.h:76)
 *   -[MLMultiArray initWithShape:dataType:error:]              (MLMultiArray.h:91)
 *   +[MLFeatureValue featureValueWithMultiArray:]              (MLFeatureValue.h:59)
 * No setter or getter of MLModelConfiguration, MLPredictionOptions or MLFeatureDescription appears
 * in the client at all, which is why those three are left with no methods of their own: the client
 * only allocates and passes them, and NSObject supplies that.
 *
 * WHAT IT ANSWERS, AND WHY THAT IS THE TRUTH. This guest has no Core ML runtime: no model compiler,
 * no inference engine, no Neural Engine, no GPU/Metal device (see MetalNoGPU -- the guest's Metal
 * answers "no device exists"), and no model bundle anywhere in the prefix. So a model cannot be
 * loaded and a prediction cannot be made, and the truthful answer to every entry point that ASKS for
 * one is an EXPLICIT FAILURE, never a fabricated model:
 *
 *   modelWithContentsOfURL:configuration:error:  nil, and *error set.
 *   compileModelAtURL:error:                     nil, and *error set.
 *   predictionFromFeatures:options:error:        nil, and *error set. (Unreachable in practice --
 *                                                no non-nil MLModel can exist -- but declared so
 *                                                the contract is complete rather than surprising.)
 *   initWithShape:dataType:error:                nil, and *error set: a multiarray is storage the
 *                                                Core ML runtime hands out, and there is no runtime.
 *   featureValueWithMultiArray:                  nil: a value can only wrap a multiarray, and no
 *                                                multiarray can be constructed (previous line).
 *
 * The NSError is reported in `MLModelErrorDomain` with `MLModelErrorGeneric` (0) -- the domain and
 * the code Apple's own MLModelError.h declare for a model that could not be produced -- and its
 * description states the fact: Core ML is unavailable in this guest. That is what "explicit failure"
 * means here: the caller gets the error object its API promises, not a nil without a reason and not
 * a placeholder that pretends to be a model.
 *
 * NOT IMPLEMENTED, and deliberately named: the entire model format and inference surface (the other
 * ~60 headers, the MLModelAsset/MLComputePlan/MLModelStructure families, MLDictionaryFeatureProvider,
 * MLSequence, the update/task APIs) is absent. Nothing in the ladder's closure demands it. No "STUB:"
 * string is printed anywhere in this image.
 *
 * NOTE FOR THE ANALYZER'S READER: scripts/closure_analyze.py classifies a demanded ObjC class by its
 * METHOD LIST -- method-free is "absence", anything else is "real: class has methods". The three
 * classes above that answer with absence carry the methods the client actually sends, so the
 * analyzer reports them as "real", which overstates them: their answers are nil and an NSError, not
 * an implementation. The method-free classification would require leaving the class empty, which
 * would make a measured client message crash instead of failing cleanly.
 */

#import <Foundation/Foundation.h>

/* Apple's own domain and generic code (MLModelError.h), used for the failure below. */
static NSString *const kCoreMLSubstituteErrorDomain = @"com.apple.CoreML";
enum { kCoreMLSubstituteErrorGeneric = 0 };

static NSError *CoreMLUnavailable(NSString *what)
{
	return [NSError errorWithDomain:kCoreMLSubstituteErrorDomain
				   code:kCoreMLSubstituteErrorGeneric
			       userInfo:@{
		NSLocalizedDescriptionKey: [NSString stringWithFormat:
			@"Core ML is not available in this guest: %@ needs a Core ML runtime, and this guest "
			@"has none (no model compiler, no inference engine, no Neural Engine, and the same "
			@"guest's Metal reports no device). Nothing was loaded and nothing was inferred.",
			what],
	}];
}

@interface MLFeatureDescription : NSObject
@end
@implementation MLFeatureDescription
@end

@interface MLModelConfiguration : NSObject
@end
@implementation MLModelConfiguration
@end

@interface MLPredictionOptions : NSObject
@end
@implementation MLPredictionOptions
@end

@interface MLMultiArray : NSObject
@end
@implementation MLMultiArray

/* MLMultiArray.h:91. The shape and data type are not even inspected: there is no runtime that could
 * back such a buffer, so no shape would succeed. */
- (instancetype)initWithShape:(NSArray *)shape
		     dataType:(NSInteger)dataType
			error:(NSError **)error
{
	(void)shape; (void)dataType;
	if (error) {
		*error = CoreMLUnavailable(@"MLMultiArray");
	}
	return nil;
}

@end

@interface MLFeatureValue : NSObject
@end
@implementation MLFeatureValue

/* MLFeatureValue.h:59. A feature value can only wrap a value that exists, and no MLMultiArray can
 * exist here (MLMultiArray's only initializer above fails), so the truthful answer is nil. */
+ (instancetype)featureValueWithMultiArray:(MLMultiArray *)value
{
	(void)value;
	return nil;
}

@end

@interface MLModel : NSObject
@end
@implementation MLModel

/* MLModel.h:37 / :44. Both factories answer nil and set the error the API promises. This is the
 * entry point DVTSmartSearch reaches first when it tries to load an embedding model for semantic
 * search; failing here is what makes the rest of its Core ML path inert instead of wrong. */
+ (instancetype)modelWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
	(void)url;
	if (error) {
		*error = CoreMLUnavailable(@"MLModel loading");
	}
	return nil;
}

+ (instancetype)modelWithContentsOfURL:(NSURL *)url
			 configuration:(MLModelConfiguration *)configuration
				 error:(NSError **)error
{
	(void)url; (void)configuration;
	if (error) {
		*error = CoreMLUnavailable(@"MLModel loading");
	}
	return nil;
}

/* MLModel+MLModelCompilation.h:35. Answers a compiled-model URL, so the declaration returns NSURL. */
+ (NSURL *)compileModelAtURL:(NSURL *)modelURL error:(NSError **)error
{
	(void)modelURL;
	if (error) {
		*error = CoreMLUnavailable(@"model compilation");
	}
	return nil;
}

/* MLModel.h:76. */
- (id)predictionFromFeatures:(id)input options:(MLPredictionOptions *)options error:(NSError **)error
{
	(void)input; (void)options;
	if (error) {
		*error = CoreMLUnavailable(@"prediction");
	}
	return nil;
}

@end
