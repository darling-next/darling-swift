//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Darling: Morphology, InflectionRule and the two AttributedString attribute keys built on them.
//
// WHY THIS FILE EXISTS (the rung that needed it). The guest's Xcode 26.3
// DVTInstrumentsUtilities.framework asks Foundation for twelve Swift symbols that the deployed
// libswiftFoundation.dylib did not export -- Foundation.Morphology, Foundation.InflectionRule and
// AttributeScopes.FoundationAttributes.InflectionRuleAttribute -- so dyld stopped at
//
//     Symbol not found: _$s10Foundation10MorphologyV17GrammaticalNumberO6pluralyA2EmFWC
//       Referenced from .../DVTInstrumentsUtilities (built for Mac OS X 14.0)
//       Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
//
// (the framework is the ordinal's blame text; the symbols are the overlay's, and Foundation
// re-exports /usr/lib/swift/libswiftFoundation.dylib). Swift's stdlib Foundation overlay has never
// carried these declarations, this build compiles without FOUNDATION_FRAMEWORK, and so the
// `#if FOUNDATION_FRAMEWORK` halves of FoundationAttributes.swift and of swift-foundation's own
// FoundationAttributes.swift -- the only place Apple's open source names them -- are all excluded
// from this module. Hence a file that declares them for this tree.
//
// WHERE EVERYTHING COMES FROM (nothing here is invented):
//
//   * the DECLARATIONS (member set, spelling, availability, raw-value ORDER, conformances) are
//     Apple's published API for this module, read out of the guest's own SDK:
//       <Xcode 26.3>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/
//         Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/x86_64-apple-macos.swiftinterface
//     (Morphology at 18184, InflectionRule at 18317, the two attribute enums at 5903/5909,
//     AttributedString.inflected() at 23473) -- the same declarations the iPhoneOS SDK carries.
//     The .swiftinterface does NOT print raw values (a test with swiftc 6.3.1 shows `case a = 1`
//     printing as `case a`), so the raw values below cannot come from there.
//
//   * the RAW VALUES and the implementations are apple/swift-corelibs-foundation
//     `Sources/Foundation/Morphology.swift` (same module name, same public API, Apache-2.0 with
//     Runtime Library Exception), which declares `case singular = 1` and so on. They are
//     independently corroborated by the SDK's Objective-C table for the same feature,
//     Foundation.framework/Headers/NSMorphology.h: NSGrammaticalNumber is `NotSet = 0, Singular,
//     Zero, Plural, PluralTwo, PluralFew, PluralMany` -- 1-based, in exactly this order, with the
//     ObjC NotSet sentinel represented on the Swift side as `Optional`. The same check holds for
//     GrammaticalGender, PartOfSpeech, GrammaticalCase, GrammaticalPerson, PronounType,
//     Determination and Definiteness in that header. NSMorphology and NSInflectionRule are
//     NS_REFINED_FOR_SWIFT, i.e. these Swift types are the refined API of those ObjC classes.
//
// WHAT IS DELIBERATELY NOT HERE (each with its reason, so a later rung reads it as a decision):
//
//   * Morphology's macOS 14 members (grammaticalCase, grammaticalPerson, pronounType,
//     determination, definiteness) and the macOS 15
//     `inflected(locale:userTermOfAddress:inflectionConcepts:)` overload. No image in this tree's
//     closure demands them yet; the SDK declares them but neither open source implements them for
//     this module, so their Codable form (which keys Apple encodes) would have to be guessed.
//     Guessing a wire format is exactly the plausible-looking answer this tree refuses.
//   * `Morphology : _ObjectiveCBridgeable` (to __NSMorphology) and the whole Objective-C side:
//     Darling's Foundation has no NSMorphology/NSInflectionRule class at all (no header, no
//     symbol), so there is nothing to bridge to. The Swift-side API is what the loader demands.
//   * the macOS 14 deprecation of CustomPronoun in favour of TermOfAddress: this tree has no
//     TermOfAddress, so the attribute would name a type that does not exist here.
//   * the two `let morphology` / `let inflect` properties of
//     AttributeScopes.FoundationAttributes. They are stored properties, so they cannot live in
//     this file's extension, and adding them to the struct would make the scope enumerate two
//     attributes whose Objective-C conversion needs the bridging above.

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct Morphology : Sendable {
    public init() {}

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public enum GrammaticalGender: Int, Hashable, Sendable {
        case feminine  = 1
        case masculine
        case neuter
    }
    public var grammaticalGender: GrammaticalGender?

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public enum PartOfSpeech: Int, Hashable, Sendable {
        case determiner = 1
        case pronoun
        case letter
        case adverb
        case particle
        case adjective
        case adposition
        case verb
        case noun
        case conjunction
        case numeral
        case interjection
        case preposition
        case abbreviation
    }
    public var partOfSpeech: PartOfSpeech?

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public enum GrammaticalNumber: Int, Hashable, Sendable {
        case singular = 1
        case zero
        case plural
        case pluralTwo
        case pluralFew
        case pluralMany
    }
    public var number: GrammaticalNumber?

    fileprivate var customPronouns: [String: CustomPronoun] = [:]
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public enum InflectionRule : Sendable {
    case automatic
    case explicit(Morphology)

    public init(morphology: Morphology) {
        self = .explicit(morphology)
    }
}

// MARK: -
// MARK: Equatable & Hashable Support

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology: Hashable {}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology.CustomPronoun: Hashable {}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension InflectionRule: Hashable {}

// MARK: -
// MARK: Codable Support

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology: Codable {
    enum CodingKeys: String, CodingKey {
        case grammaticalGender
        case partOfSpeech
        case number
        case customPronouns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.grammaticalGender = try container.decodeIfPresent(GrammaticalGender.self, forKey: .grammaticalGender)
        self.partOfSpeech = try container.decodeIfPresent(PartOfSpeech.self, forKey: .partOfSpeech)
        self.number = try container.decodeIfPresent(GrammaticalNumber.self, forKey: .number)
        self.customPronouns = try container.decodeIfPresent([String: CustomPronoun].self, forKey: .customPronouns) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let grammaticalGender = grammaticalGender {
            try container.encode(grammaticalGender, forKey: .grammaticalGender)
        }
        if let partOfSpeech = partOfSpeech {
            try container.encode(partOfSpeech, forKey: .partOfSpeech)
        }
        if let number = number {
            try container.encode(number, forKey: .number)
        }
        if !customPronouns.isEmpty {
            try container.encode(customPronouns, forKey: .customPronouns)
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology.CustomPronoun: Codable {}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology.GrammaticalGender: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "feminine":  self = .feminine
        case "masculine": self = .masculine
        case "neuter":    self = .neuter
        default: throw CocoaError(.coderInvalidValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .feminine:  try container.encode("feminine")
        case .masculine: try container.encode("masculine")
        case .neuter:    try container.encode("neuter")
        }
    }
}

// The strings are the CLDR plural categories the grammar engine uses, as in Apple's own
// implementation of this type.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology.GrammaticalNumber: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "one":   self = .singular
        case "zero":  self = .zero
        case "other": self = .plural
        case "two":   self = .pluralTwo
        case "few":   self = .pluralFew
        case "many":  self = .pluralMany
        default: throw CocoaError(.coderInvalidValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .singular:   try container.encode("one")
        case .zero:       try container.encode("zero")
        case .plural:     try container.encode("other")
        case .pluralTwo:  try container.encode("two")
        case .pluralFew:  try container.encode("few")
        case .pluralMany: try container.encode("many")
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology.PartOfSpeech: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "determiner":   self = .determiner
        case "pronoun":      self = .pronoun
        case "letter":       self = .letter
        case "adverb":       self = .adverb
        case "particle":     self = .particle
        case "adjective":    self = .adjective
        case "adposition":   self = .adposition
        case "verb":         self = .verb
        case "noun":         self = .noun
        case "conjunction":  self = .conjunction
        case "numeral":      self = .numeral
        case "interjection": self = .interjection
        case "preposition":  self = .preposition
        case "abbreviation": self = .abbreviation
        default: throw CocoaError(.coderInvalidValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .determiner:   try container.encode("determiner")
        case .pronoun:      try container.encode("pronoun")
        case .letter:       try container.encode("letter")
        case .adverb:       try container.encode("adverb")
        case .particle:     try container.encode("particle")
        case .adjective:    try container.encode("adjective")
        case .adposition:   try container.encode("adposition")
        case .verb:         try container.encode("verb")
        case .noun:         try container.encode("noun")
        case .conjunction:  try container.encode("conjunction")
        case .numeral:      try container.encode("numeral")
        case .interjection: try container.encode("interjection")
        case .preposition:  try container.encode("preposition")
        case .abbreviation: try container.encode("abbreviation")
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension InflectionRule: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let it = try? container.decode(Bool.self), it == true {
            self = .automatic
        } else {
            let it = try container.decode(Morphology.self)
            self = .explicit(it)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .automatic:                try container.encode(true)
        case .explicit(let morphology): try container.encode(morphology)
        }
    }
}

// MARK: -
// MARK: Inflection Availability

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension InflectionRule {
    /// Whether inflection will edit strings for the specified language, given as a BCP 47 language
    /// identifier.
    ///
    /// `false` for every language: the engine that answers this on Darwin is part of the closed
    /// Foundation framework, and nothing in this tree--Darling's Foundation, or ICU 66 through
    /// libicucore--implements grammatical inflection. Apple's own open-source Foundation gives the
    /// same answer from the same lack, where `InflectionRule.canInflect(language:)` is false and
    /// `canInflectPreferredLocalization` is false; the value is real, not a placeholder.
    public static func canInflect(language: String) -> Bool {
        return false
    }

    /// Same as `canInflect(language:)`, for the language of the user's preferred localization.
    public static var canInflectPreferredLocalization: Bool {
        return false
    }
}

// MARK: -
// MARK: Per-Language Features

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology {
    public func customPronoun(forLanguage language: String) -> CustomPronoun? {
        return customPronouns[language.lowercased()]
    }

    mutating public func setCustomPronoun(_ pronoun: CustomPronoun?, forLanguage language: String) throws {
        if let pronoun = pronoun {
            let result = pronoun.validate(forLanguage: language)
            if !result {
                throw CocoaError(.keyValueValidation)
            }
        }

        customPronouns[language.lowercased()] = pronoun
    }

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public struct CustomPronoun : Sendable {
        public init() {}

        public static func isSupported(forLanguage language: String) -> Bool {
            let indexAtTwo = language.index(language.startIndex, offsetBy: 2)
            // For now we only support English custom pronoun
            return language.count >= 2 &&
                language.lowercased().starts(with: "en") &&
                (language.count == 2 ||
                 language[indexAtTwo ..< language.index(after: indexAtTwo)] == "-" ||
                 language[indexAtTwo ..< language.index(after: indexAtTwo)] == "_")
        }

        public static func requiredKeys(forLanguage language: String) -> [PartialKeyPath<Self>] {
            guard self.isSupported(forLanguage: language) else {
                return []
            }
            return [\.subjectForm, \.objectForm, \.possessiveForm, \.possessiveAdjectiveForm, \.reflexiveForm]
        }

        fileprivate func validate(forLanguage language: String) -> Bool {
            guard Self.isSupported(forLanguage: language) else {
                return false
            }

            for keyPath in Self.requiredKeys(forLanguage: language) {
                let value: Any? = self[keyPath: keyPath]
                if value == nil {
                    return false
                }
            }

            return true
        }

        public var subjectForm: String?
        public var objectForm: String?
        public var possessiveForm: String?
        public var possessiveAdjectiveForm: String?
        public var reflexiveForm: String?
    }
}

// MARK: -
// MARK: NSAttributedString Keys

// The SDK's Foundation headers carry no NSMorphologyAttributeName/NSInflectionRuleAttributeName (the
// Objective-C side of this feature is not in this tree), so the two keys are declared here with the
// raw values Apple's own open-source Foundation uses. They are what the two attribute keys below
// name themselves with; nothing else reads them.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension NSAttributedString.Key {
    public static let morphology = NSAttributedString.Key(rawValue: "NSMorphology")
    public static let inflectionRule = NSAttributedString.Key(rawValue: "NSInflect")
}

// MARK: -
// MARK: Attribute Scope

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributeScopes.FoundationAttributes {
    /// The value of this attribute is a `Morphology`: the grammatical properties a grammatical
    /// agreement rule reads.
    @frozen
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    public enum MorphologyAttribute : CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = Morphology
        public static let name = NSAttributedString.Key.morphology.rawValue
        public static let markdownName = "morphology"
    }

    /// The value of this attribute is an `InflectionRule`: how the tagged run is to be inflected.
    @frozen
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    public enum InflectionRuleAttribute : CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = InflectionRule
        public static let name = NSAttributedString.Key.inflectionRule.rawValue
        public static let markdownName = "inflect"
    }
}

// MARK: -
// MARK: Inflection

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedString {
    /// Returns a string with the inflectional rules of its runs applied.
    ///
    /// The transformation is scoped to the tagged runs: Apple documents it in the SDK's own header
    /// (Foundation.framework/Headers/NSAttributedString.h, `NSAttributedString(NSMorphology)`) as
    /// "if the string has portions tagged with NSInflectionRuleAttributeName that have no format
    /// specifiers, create a new string with those portions inflected by following the rule in the
    /// attribute". A string whose runs ask for no inflection therefore has exactly one answer, the
    /// receiver, and that is what this returns--an answer measured against the documented rule, not
    /// a shrug.
    ///
    /// A string that does ask for inflection cannot be served here, and stops instead of returning
    /// an uninflected string that would look like a correct answer: the grammar engine behind
    /// inflection is part of Darwin's closed-source Foundation, and Apple's own open-source
    /// Foundation -- which likewise has no engine -- does not ship this method at all and answers
    /// `InflectionRule.canInflect(language:)` with false.
    public func inflected() -> AttributedString {
        for run in runs {
            let attributes = run.attributes
            if attributes[AttributeScopes.FoundationAttributes.InflectionRuleAttribute.self] != nil ||
               attributes[AttributeScopes.FoundationAttributes.MorphologyAttribute.self] != nil {
                fatalError("""
                    AttributedString.inflected() is not implemented on Darling: the run at \
                    \(run.range) carries an inflection attribute, and grammatical inflection is \
                    Darwin Foundation's closed-source grammar engine, which this tree does not \
                    implement (InflectionRule.canInflect(language:) answers false from the same \
                    lack). Returning the uninflected string would be a silently wrong answer.
                    """)
            }
        }
        return self
    }
}
