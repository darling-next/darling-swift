// libswiftNaturalLanguage.dylib -- the Swift half of a TRUTHFUL substitute for Apple's
// /usr/lib/swift/libswiftNaturalLanguage.dylib.
//
// WHY IT EXISTS. The Xcode 26.3 load-time ladder reaches this image through DVTSmartSearch:
//
//   Library not loaded: /usr/lib/swift/libswiftNaturalLanguage.dylib
//   Referenced from: .../Xcode.app/Contents/SharedFrameworks/DVTSmartSearch.framework/Versions/A/DVTSmartSearch
//
// DVTSmartSearch links it STRONGLY (compatibility 1.0.0, current 4.3.0) and binds FOUR symbols from
// the dependency field `libswiftNaturalLanguage`, all through the bind table (measured with
// `llvm-objdump --macho --dyld-info`, per dependency field, never by substring). DNTDocumentationSupport
// also names the image, but only WEAKLY and binds ZERO names from it:
//
//   extension NLEmbedding.enumerateNeighbors(for:maximumCount:distanceType:using:)
//   extension NLEmbedding.vector(for:)
//   extension NLContextualEmbeddingResult.enumerateTokenVectors(in:using:)
//   extension NLTagger.tag(at:unit:scheme:)
//
// SOURCE SEARCH, because "Apple-private" is not the same as "no source". (a) apple/swift DID publish
// this overlay: `stdlib/public/SDK/NaturalLanguage/{NLTagger,NLTokenizer,NLLanguageRecognizer}.swift`
// exists at tag swift-5.0-RELEASE (Apache-2.0 with Runtime Library Exception) and is GONE from the
// SDK-overlay directory by swift-5.5 -- Swift.org stopped shipping the Darwin overlays. (b) Three of
// the four demanded names POSTDATE that source and are in no open-source revision: NLEmbedding's
// overlay extensions (macOS 11/10.15) and NLContextualEmbeddingResult's (macOS 14). (c) The 5.0
// source that does exist cannot be compiled here as it stands: its bodies call the framework's
// API-note-renamed `__`-prefixed methods (`__tag(at:unit:scheme:tokenRange:)` and friends), which
// neither Darling's SDK nor this tree's NaturalLanguage substitute implements, so importing it would
// produce an overlay that traps the moment a client used it. The route is therefore a clean-room
// module: the SHAPES come from Apple's own two published descriptions of the ABI --
//   <Xcode>/.../MacOSX.sdk/usr/lib/swift/NaturalLanguage.swiftmodule/x86_64-apple-macos.swiftinterface
//   <Xcode>/.../MacOSX.sdk/usr/lib/swift/libswiftNaturalLanguage.tbd
// -- and the answers are the truth about this guest (below), never a fabricated value.
//
// WHAT IT ANSWERS, AND WHY THAT IS THE TRUTH. Every one of the four entry points exists to ask a
// LANGUAGE MODEL something, and this guest has no language assets, no tokenizer, no embedding store
// and no tagger engine (see the Objective-C half, overlays/NaturalLanguage/NaturalLanguage.m, whose
// factories all answer nil). So:
//
//   NLEmbedding.vector(for:)                      nil  -- there is no embedding, so no word has a vector.
//   NLEmbedding.enumerateNeighbors(for:...)       returns without calling `using` -- with no embedding
//                                                 there are no neighbours to enumerate, and inventing
//                                                 one would be worse than reporting none.
//   NLContextualEmbeddingResult.enumerateTokenVectors(in:using:)
//                                                 likewise: no result object can exist (its only
//                                                 producer answers nil), so there are no token vectors.
//   NLTagger.tag(at:unit:scheme:)                 (nil, index..<index) -- no tagger instance can be
//                                                 created (initWithTagSchemes: answers nil), and if one
//                                                 were asked, no tag is known and no token range can be
//                                                 reported; an EMPTY range at the index is the absence
//                                                 of information rather than a made-up span.
//
// NOT IMPLEMENTED, and deliberately named: the other 26 symbols Apple's .tbd carries (NLTokenizer,
// NLLanguageRecognizer, NLModel and the vector/neighbour variants) are absent. Nothing in the
// ladder's closure demands them; a client that binds them fails at LOAD rather than calling something
// that answers wrongly. No "STUB:" string is printed, and no method here returns a made-up value.

import Foundation
import _DarlingNaturalLanguageShims

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NLEmbedding {
	// Apple's declaration: NaturalLanguage.swiftinterface, `extension NaturalLanguage.NLEmbedding`.
	@nonobjc public func vector(for string: String) -> [Double]? {
		_ = string
		return nil
	}

	@nonobjc public func enumerateNeighbors(
		for string: String, maximumCount maxCount: Int, distanceType: NLDistanceType = .cosine,
		using block: (String, Double) -> Bool)
	{
		_ = (string, maxCount, distanceType, block)
	}
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NLContextualEmbeddingResult {
	@nonobjc public func enumerateTokenVectors(
		in range: Range<String.Index>, using block: ([Double], Range<String.Index>) -> Bool)
	{
		_ = (range, block)
	}
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NLTagger {
	@nonobjc public func tag(
		at index: String.Index, unit: NLTokenUnit, scheme: NLTagScheme)
		-> (NLTag?, Range<String.Index>)
	{
		_ = (index, unit, scheme)
		return (nil, index..<index)
	}
}
