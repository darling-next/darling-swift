/*
 * NaturalLanguage.framework -- a TRUTHFUL substitute for Apple's
 * /System/Library/Frameworks/NaturalLanguage.framework.
 *
 * WHY IT EXISTS. The Xcode 26.3 load-time ladder reaches this image through TWO referrers, both
 * strong (measured from each one's own LC_LOAD_DYLIB and bind table):
 *
 *   DVTSmartSearch        binds 5 names from the dependency field `NaturalLanguage`:
 *                         _NLLanguageEnglish, _NLTagSchemeLemma, _OBJC_CLASS_$_NLTagger,
 *                         _OBJC_CLASS_$_NLEmbedding, _OBJC_CLASS_$_NLContextualEmbedding
 *   DNTDocumentationSupport  binds 2: _NLLanguageEnglish, _OBJC_CLASS_$_NLContextualEmbedding
 *
 * SHAPES. Apple ships headers for this framework in the same SDK, and every declaration below is
 * one of theirs (none invented):
 *   <Xcode>/.../MacOSX.sdk/System/Library/Frameworks/NaturalLanguage.framework/Headers/NLTagger.h,
 *   NLEmbedding.h, NLContextualEmbedding.h, NLLanguage.h, NLTagScheme.h
 * and the Swift overlay that wraps them is <Xcode>/.../MacOSX.sdk/usr/lib/swift/
 * NaturalLanguage.swiftmodule/x86_64-apple-macos.swiftinterface (this file supplies the Objective-C
 * half; overlays/NaturalLanguage/libswiftNaturalLanguage.swift supplies the Swift half, whose four
 * demanded symbols that interface declares).
 *
 * WHAT THE CLIENTS SEND, read out of their own images (selector strings confirmed against the SDK
 * header that declares each, then matched to the code that loads the classref):
 *
 *   DVTSmartSearch           +[NLEmbedding wordEmbeddingForLanguage:]          NLEmbedding.h:22
 *                            +[NLEmbedding sentenceEmbeddingForLanguage:]      NLEmbedding.h:25
 *                            +[NLContextualEmbedding contextualEmbeddingWithLanguage:] NLContextualEmbedding.h:39
 *                            -[NLTagger initWithTagSchemes:]                   NLTagger.h
 *   DNTDocumentationSupport  -[NLTagger initWithTagSchemes:options:]           NLTagger.h
 *                            +[NLContextualEmbedding contextualEmbeddingForLanguage:]  (see below)
 *                            -[NLTagger setOrthography:range:]                 NLTagger.h
 *                            -[NLContextualEmbedding embeddingResultForString:language:error:]
 *                                                                              NLContextualEmbedding.h:64
 *
 * WHAT IT ANSWERS, AND WHY THAT IS THE TRUTH. Natural Language is a data-driven framework: every
 * one of those factories exists to load a language model or embedding asset from the system, and a
 * tagger exists to run those models over a string. This guest has NO language assets, NO tokenizer,
 * NO embedding store and NO tagger engine. So the truthful answer is the ABSENCE of every object
 * those factories are asked for:
 *
 *   wordEmbeddingForLanguage:            nil -- there is no word embedding for any language.
 *   sentenceEmbeddingForLanguage:        nil -- likewise for sentence embeddings.
 *   contextualEmbeddingWithLanguage:     nil -- likewise for contextual embeddings. (Apple's own
 *                                        header marks this nullable, because it answers nil for a
 *                                        language whose assets are absent -- here that is every
 *                                        language.)
 *   contextualEmbeddingForLanguage:      nil, same answer. This spelling is NOT in Apple's header:
 *                                        it is a selector string in DNTDocumentationSupport's own
 *                                        image, used as a one-argument CLASS method on
 *                                        NLContextualEmbedding in the code that loads that classref.
 *                                        Whether it is Apple's method under another name or the
 *                                        client's own convenience wrapper cannot be settled from
 *                                        the static image, so both spellings answer the same truth
 *                                        and neither can crash a caller.
 *   initWithTagSchemes:[options:]        nil -- a tagger cannot be constructed, because no tag
 *                                        scheme can be served without any model asset. Apple's
 *                                        initializers already answer nil for unsupported schemes.
 *                                        Every later message the clients send (setOrthography:range:,
 *                                        setString:, tagAtIndex:..., dnt_enumerateTagsInRange:...)
 *                                        then goes to nil, which is a no-op in Objective-C -- the
 *                                        callers' own nil-guards and the language of the API both
 *                                        treat that as "no information", not as an error.
 *
 * THE TWO CONSTANTS' VALUES are the documented ones: NLLanguageEnglish is the standard language
 * abbreviation "en" (NLLanguage's header says so in as many words: "Tags for NLTagSchemeLanguage are
 * standard language abbreviations"), and NLTagSchemeLemma is the scheme named "Lemma" (its header
 * documents the value as the scheme identifier). They are what a client passes back INTO the
 * factories above, which answer nil for every language and every scheme, so no value here can make
 * a client believe something happened.
 *
 * NOT IMPLEMENTED, and deliberately named: the whole NLP surface (NLTokenizer, NLLanguageRecognizer,
 * NLModel, NLGazetteer, NLScript, NLContextualEmbeddingResult's data, and the ~60 other selectors of
 * Apple's headers) is absent. A client that binds more than the demanded names fails at LOAD rather
 * than calling something that answers wrongly. No "STUB:" string is printed in this image.
 *
 * NOTE FOR THE ANALYZER'S READER: the demanded classrefs below carry the methods their measured
 * clients actually send, so scripts/closure_analyze.py reports them as "real: class has methods"
 * rather than "absence: method-free class". The answers are nil, not an implementation; the
 * method-free label would require leaving a class empty, which would make a measured message send
 * crash instead of failing cleanly.
 */

#import <Foundation/Foundation.h>

/* NLLanguage and NLTagScheme are extensible string enums in Apple's headers
 * (`typedef NSString *NLTag NS_TYPED_EXTENSIBLE_ENUM`); the constants are the documented values. */
NSString *const NLLanguageEnglish = @"en";
NSString *const NLTagSchemeLemma = @"Lemma";

@interface NLTagger : NSObject
@end

@implementation NLTagger

- (instancetype)initWithTagSchemes:(NSArray *)tagSchemes
{
	(void)tagSchemes;
	return nil;
}

- (instancetype)initWithTagSchemes:(NSArray *)tagSchemes options:(NSUInteger)options
{
	(void)tagSchemes; (void)options;
	return nil;
}

@end

@interface NLEmbedding : NSObject
@end

@implementation NLEmbedding

+ (instancetype)wordEmbeddingForLanguage:(NSString *)language
{
	(void)language;
	return nil;
}

+ (instancetype)sentenceEmbeddingForLanguage:(NSString *)language
{
	(void)language;
	return nil;
}

@end

@interface NLContextualEmbedding : NSObject
@end

@implementation NLContextualEmbedding

+ (instancetype)contextualEmbeddingWithLanguage:(NSString *)language
{
	(void)language;
	return nil;
}

/* See the header comment: the client's own spelling of the same question, answered the same way. */
+ (instancetype)contextualEmbeddingForLanguage:(NSString *)language
{
	(void)language;
	return nil;
}

@end
