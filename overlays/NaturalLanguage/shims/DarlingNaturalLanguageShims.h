// Declarations of the NaturalLanguage framework types the Swift overlay extends, so the overlay can
// be built on Linux against a Clang module that Apple's SDK would otherwise supply. The declarations
// are Apple's own, taken from the framework's public headers
// (<Xcode>/.../MacOSX.sdk/System/Library/Frameworks/NaturalLanguage.framework/Headers/NLEmbedding.h,
// NLTagger.h, NLContextualEmbedding.h, NLTagScheme.h, NLLanguage.h) -- the same headers the SDK ships
// -- and reduced to the types the four demanded overlay entry points name. Only the SHAPE matters
// here: the overlay's methods never call the framework (see libswiftNaturalLanguage.swift), and the
// mangled names the overlay exports encode exactly these type names, which is why they are declared
// with Apple's spellings and annotations rather than invented ones.
#ifndef DARLING_NATURALLANGUAGE_SHIMS_H
#define DARLING_NATURALLANGUAGE_SHIMS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// NLEmbedding.h
typedef NS_ENUM(NSInteger, NLDistanceType) {
	NLDistanceTypeCosine
};
typedef double NLDistance;

// NLTagScheme.h and NLTagger.h. NS_TYPED_EXTENSIBLE_ENUM is what makes these import as Swift string
// enums (the `...a` mangling), exactly as Apple's headers declare them.
typedef NSString *NLTagScheme NS_TYPED_EXTENSIBLE_ENUM;
typedef NSString *NLTag NS_TYPED_EXTENSIBLE_ENUM;

// NLTagger.h
typedef NS_ENUM(NSInteger, NLTokenUnit) {
	NLTokenUnitWord = 0,
	NLTokenUnitSentence = 1,
	NLTokenUnitParagraph = 2,
	NLTokenUnitDocument = 3
};

// The three classes the demanded overlay entry points extend. No methods are declared: the overlay
// never sends one, and a method list here would only be a claim about an implementation this tree
// does not have.
__attribute__((swift_name("NLTagger")))
@interface NLTagger : NSObject
@end

__attribute__((swift_name("NLEmbedding")))
@interface NLEmbedding : NSObject
@end

__attribute__((swift_name("NLContextualEmbeddingResult")))
@interface NLContextualEmbeddingResult : NSObject
@end

NS_ASSUME_NONNULL_END

#endif
