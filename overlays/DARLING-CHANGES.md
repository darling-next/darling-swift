# Darling changes to vendored upstream sources

## URLResourceValues.isAliasFile

`Foundation/URLResourceValues.swift` exposes the read-only `Bool?` getter from
vendored corelibs `Sources/Foundation/URL.swift` and
[Swift Foundation 6.2](https://github.com/swiftlang/swift-foundation/blob/swift-6.2-RELEASE/Sources/FoundationEssentials/URL/URL.swift#L597).
It uses this overlay's existing `NSNumber` resource-value bridge. Unrequested
or unavailable native metadata remains `nil`, not a manufactured `false`.
The getter does not add a Finder-alias or bookmark metadata provider.

Regenerate the Foundation overlay payload before using the normal installation
rules described below; the host Swift CMake member imports the built dylib.

## URLResourceValues.path

`Foundation/URLResourceValues.swift` reuses the read-only `String?` resource
getter from vendored corelibs `Sources/Foundation/URL.swift` and
[Swift Foundation 6.2](https://github.com/swiftlang/swift-foundation/blob/swift-6.2-RELEASE/Sources/FoundationEssentials/URL/URL.swift#L284).
It reads `.pathKey` from the existing resource dictionary; native
`CFURLCopyFileSystemPath(..., kCFURLPOSIXPathStyle)` supplies the value.
Unrequested or unavailable values remain `nil`. The getter neither substitutes
`URL.path` for missing metadata nor resolves the path through a symbolic link.

## StringProtocol.commonPrefix(with:options:)

`Foundation/NSStringAPI.swift` restores the unconstrained Darwin-overlay
`StringProtocol` API through the existing `NSString` bridge, including
`Substring` arguments. Native `NSString.commonPrefixWithString:options:`
provides canonical, literal and case-insensitive comparisons while retaining
the receiver's spelling and complete extended grapheme clusters.
Regenerate the Foundation overlay payload before normal installation;
adding the Swift source alone does not update the imported dylib.

## NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(_:)

`Foundation/NSKeyedUnarchiver+Refinement.swift` restores the pre-secure-coding top-level
unarchive API that released clients still bind. The Swift 6.2.4 toolchain payload's
`libswiftFoundation.dylib` does not define the symbol, and swift-foundation 6.3.3 does not
carry it, but swift-corelibs-foundation's Darwin overlay does
(`Darwin/Foundation-swiftoverlay/NSCoder.swift`, `Data` overload), and prefire 5.6.1 binds
`_$sSo17NSKeyedUnarchiverC10FoundationE31unarchiveTopLevelObjectWithDatayypSgAC0I0VKFZ`
eagerly: prefire 5.6.1 and Sourcery 2.3.0 both abort in dyld with `Symbol not found ...
Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation` before
`--version` runs. The overlay method is a typed call to darling-foundation's restored native
`+unarchiveTopLevelObjectWithData:error:` (the selector Apple's Foundation declares through
macOS 10.14), not a hand-built IMP or NSError out-pointer: that backend reads without secure
coding, decodes `NSKeyedArchiveRootObjectKey` through `-decodeTopLevelObjectForKey:error:`,
and reports Cocoa 4865 (`NSCoderValueNotFoundError`) for a missing root and Cocoa 4864
(`NSCoderReadCorruptError`) for unreadable bytes, including the coder's
`NSInvalidUnarchiveOperationException` "Improperly formatted archive" path. The Swift
`throws` contract therefore holds instead of aborting. `overlays/tests/unarchive_top_level.swift`
asserts the valid numeric/string/dictionary roots, both error codes and the corrupt property
list path.

## Stored Swift errors used by Mercury

`Foundation/NSError.swift` includes the real `MachError: _BridgedStoredNSError` type and
`MachErrorCode: _ErrorCodeProtocol` conformance from the vendored corelibs
`Darwin/Foundation-swiftoverlay/NSError.swift` (also present in upstream
`swift-5.9-RELEASE`). Only `NSError.domain` becomes `domain()` for Darling's headers.
The stored strong `NSError` reference, domain precondition, `Int32` Darwin code mapping,
and shared bridging, user-info, equality and hashing implementations are retained.
`Darwin/MachError.swift` already provides the real `MachErrorCode` enum; no metadata or
export aliases are manufactured.

`Foundation/CocoaError.swift` adds `userCancelled` on both `Code` and the error type
(3072); `Foundation/POSIXError.swift` adds `ECANCELED`, returning Darwin's enum case
rather than a host errno. These bodies are from the same upstream Darwin overlay.
The existing Foundation source glob compiles all three files; no vendored
corelibs changes are required. The focused `DARLING_SWIFT_FOUNDATION_ONLY=1`
recipe builds the full overlay. After its output replaces the owned payload,
Darling's normal build links that binary directly and the Swift member's normal
install rules ship it under `R/libexec/darling/usr/lib/swift`. Publish a complete
image into a new runtime root `R`; writable guest state `P` is not a second system
library deployment. Build/install success alone is not guest API or workload acceptance.


`build.sh` fetches [apple/swift-foundation](https://github.com/apple/swift-foundation) at a pinned
commit (`dbacc67779dc0a41ddc9493acbaa332d76c9fb03`, tag `swift-6.3.3-RELEASE`) and compiles the files
its `UPSTREAM_FILES` and `UPSTREAM_INTL_FILES` lists name in place. Those are byte-identical to
upstream, so they are not vendored here. The swift-foundation files this overlay has to change are
not taken from the checkout; they live in `Foundation/` and each one's reason is below, measured
rather than assumed.
[apple/swift-collections](https://github.com/apple/swift-collections) is fetched the same way, at
`c11818f3cae0780656baa430b49e7f163f08dffd` (tag `1.1.6`), and nothing of it is vendored.

Set `SWIFT_FOUNDATION_SRC` or `SWIFT_COLLECTIONS_SRC` to an existing checkout of the matching commit
to build offline. Neither checkout is ever written to, so no patch is applied to a tree you supply.
To see exactly how one of the override files diverges, diff it against the checkout, for example
`diff -u "$src/Sources/FoundationEssentials/AttributedString/AttributedStringProtocol.swift" overlays/Foundation/AttributedStringProtocol.swift`.

Both projects are Apache License v2.0 with the Runtime Library Exception. Upstream file headers are
preserved in the files kept here, and swift-foundation's `LICENSE.md` and `NOTICE.txt` sit
beside them.

`Foundation/Locale+Language.swift` was vendored by the Locale work and is byte-identical to
`dbacc67`, so it moves into the fetch list here. `Foundation/Locale+Components.swift` stays, because
it diverges by 7 lines, and `Foundation/Locale+Darling.swift` stays because it is Darling-written
rather than upstream code. Both are documented below.

`Locale.Language`, `Locale.LanguageCode`, `Locale.Region` and `Locale.Currency` all live in
`FoundationEssentials`, which does not link ICU: they are value wrappers over a string identifier
plus static ISO code tables. Only the accessors that *reach* them from a `Locale` live in
`FoundationInternationalization`, and those are reimplemented over Darling's `NSLocale` instead
(below). The ICU-backed format styles are a different case and do use ICU, Darling's own; see
"ICU-backed format styles" below.
## Darling-specific adaptations

The other files in `Foundation/` come from the Swift 5.4 Darwin overlay and predate this mechanism;
`README.md` describes them.

## Which files are swift-foundation's, and how to check

Which files count as swift-foundation's is a provenance claim, and provenance cannot be settled by diffing against
swift-foundation alone: this overlay's other lineage is the Swift 5.4 Darwin overlay, and both
descend from the same original code, so a file being close to swift-foundation proves nothing.
Diffing against **both** lineages does settle it. Against
`release-5.4/stdlib/public/Darwin/Foundation` and `swift-foundation/Sources/FoundationEssentials`,
counting changed lines:

- `Pointers+DataProtocol.swift`, `Collections+DataProtocol.swift`, `ContiguousBytes.swift` and
  `DataProtocol.swift` are **byte-identical to the 5.4 overlay** while differing from
  swift-foundation by 2, 7, 11 and 38 lines. They look like near-pristine swift-foundation files and
  are not; they are 5.4's.
- `Codable.swift` is closer to 5.4 (52 changed lines against 66).
- The swift-foundation files kept here have **no 5.4 counterpart at all**, which is what fixes their lineage.

One file is genuinely undetermined and is flagged rather than assumed: `DateInterval.swift` is
closer to swift-foundation (57 changed lines) than to 5.4 (87), while `README.md` attributes it to
the 5.4 overlay. It is identical to neither, so it is adapted, and this file does not claim to know
from which. Anyone recounting should run the two-way diff rather than a one-way one, and should
expect to reach the same list only if they use the same provenance list.

## The swift-foundation files that are not taken from the checkout

Each is described here, except `Locale+Components.swift` (under the `Locale` entries below) and the
ICU formatting ones (under "ICU-backed format styles").

### Why these are override files rather than patches

The general rule is to carry a divergence in whichever form is smaller, counted as **lines the
repository carries**. That convention matters and belongs next to any such table: a stricter count
on the patch side, dropping diff metadata or a patch's own explanatory header, biases the comparison
by exactly what it strips, while an override file is carried whole including its upstream licence
header and any comment explaining the reduction. `CodableUtilities.swift` is the clean example of
the mirror image: of its 19 lines, 11 are the Apache header and about 4 are the comment saying what
was dropped, so a divergence-only count would score it at about 4 and flatter the override form by
the same mechanism a metadata-stripped count flatters the patch form. Count what lands in the tree,
on both sides.

Per file, that gives a split answer:

| file | patch | file | smaller |
|---|---|---|---|
| `CodableUtilities.swift` | 696 lines | 19 lines | override |
| `String+Comparison.swift` | 775 lines | 21 lines | override |
| `AttributedStringProtocol.swift` | 57 lines | 271 lines | patch |
| `Locale+Components.swift` | 23 lines | 2,086 lines | patch |

The patch column is raw `diff -u` output; a committed patch file would also carry a short header
saying why it exists, which adds a handful of lines to that side and changes none of the four
directions. All four are kept as override files anyway, so that this overlay has one mechanism rather than two
for a saving of 57 lines on one file. That is a deliberate departure from the rule and is recorded
here rather than left to look like the rule endorsing it. If a patch step is ever added,
`Locale+Components.swift` is the strongest candidate by a factor of ninety, and the patch must be
applied to a copy of the checkout, never to the checkout itself, since `SWIFT_FOUNDATION_SRC` can
point at a shared or read-only tree.

- **`CodableUtilities.swift`, reduced to two declarations.** Only `EmptyCodingKeys` and
  `DefaultAssociatedValueCodingKeys1` are kept, which is all that `AttributedString`'s
  `CodableWithConfiguration` conformances reference. Taking the file whole was measured and does not
  work: it needs `JSON/`, which needs `Decimal/` and `Base64.swift`, and that stack then collides
  with the 5.4 JSON and property-list code this overlay already ships. The collisions are
  `invalid redeclaration of '_plistNull'`, `invalid redeclaration of '_PlistDecodingStorage'` and
  `'_PlistDecodingStorage' is ambiguous for type lookup`, plus 22 further errors inside
  `PlistEncoder.swift` and 6 inside `JSONEncoder.swift`. Replacing the 5.4 JSON and property-list
  stack with swift-foundation's is a separate piece of work with its own symbol-diff acceptance, not
  a side effect of adding `AttributedString`.

- **`String+Comparison.swift`, reduced to the two UTF-8 code-unit constants.** `StringBlocks.swift`
  needs `UTF8.CodeUnit.newline` and `.carriageReturn`. Taking the file whole was measured: with
  `UnicodeScalar.swift` and `BidirectionalCollection.swift` added it still fails with 80 errors, 72
  of which are the same defect that forces the next entry, `String.CompareOptions` importing as a
  plain raw-value struct instead of an `OptionSet`. The remaining 8 are `BuiltInUnicodeScalarSet`
  (whose file imports the `_FoundationCShims` C target) and `RegexPatternCache`.

- **`AttributedStringProtocol.swift`, with `range(of:options:locale:)` and its `_range` helper
  omitted.** Both declare a `String.CompareOptions = []` default argument, which does not type-check
  for the same reason. The root cause is not `NSString.h`, which declares the type correctly with
  `NS_OPTIONS`; it is `src/external/foundation/include/Foundation/NSObjCRuntime.h`, whose
  `NS_OPTIONS` macro omits the `flag_enum` and `enum_extensibility(open)` attributes that make the
  Clang importer present the type as an `OptionSet`. `CFAvailability.h` in the same project already
  applies both through `__CF_OPTIONS_ATTRIBUTES`, so `CF_OPTIONS` types always imported correctly
  and `NS_OPTIONS` was the lone holdout, across 46 typedefs in 28 headers. It is fixed in
  darling-foundation#38, which needs a darling-swift companion because correcting the import also
  changes how those constants are spelled in Swift. When both land, this entry and the one above
  should be revisited and should disappear. No binary in the macOS 26 app corpus binds either
  omitted symbol.

- **`Locale.Components` is excluded from the build.** In
  `Foundation/Locale+Components.swift` it is kept verbatim but wrapped in `#if
  DARLING_LOCALE_COMPONENTS`, which nothing defines. Two things block it, both in Darling's
  `Calendar` and `TimeZone` rather than in the type itself: its `icuIdentifier` property calls
  `Calendar.Identifier.cldrIdentifier`, `Calendar.Identifier.legacyKeywordKey` and
  `TimeZone.legacyKeywordKey`, and its synthesised `Codable` conformance needs a `Codable`
  `Calendar.Identifier`. This overlay's `Calendar` and `TimeZone` come from the Swift 5.4 Darwin
  overlay, not from swift-foundation, and have none of those but `cldrIdentifier`, which
  `FormattingSupport.swift` supplies for the date styles. `icuIdentifier` is the whole point of
  the type (it is how a `Locale.Components` turns back into a locale identifier), so a copy without
  it would be a public type that cannot do the one job it exists for. Excluding it costs nothing
  against measured demand: no binary in the macOS 26 app corpus binds a `Locale.Components` symbol.
  Everything else in the file, including `Locale.Script`, `Locale.Collation`,
  `Locale.NumberingSystem`, `Locale.Weekday`, `Locale.HourCycle`, `Locale.MeasurementSystem`,
  `Locale.Subdivision`, `Locale.Variant`, `ICULegacyKey` and the ISO language, region and script
  tables, is compiled unmodified.
- **`Foundation/Locale+Darling.swift` is a Darling reimplementation, not upstream code.** It
  supplies the four accessors that reach the vendored types from a `Locale`: `Locale.language`,
  `Locale.region`, `Locale.currency` and `Locale.Language.languageCode`. Upstream implements these
  in `FoundationInternationalization/Locale/Locale+Components_ICU.swift` and the `_Locale` protocol,
  reading components straight out of ICU through `uloc_getLanguage`, `uloc_getCountry` and friends.
  This overlay's `Locale` is the Swift 5.4 SDK overlay's wrapper around `NSLocale`, which has no
  such internals, so the components are read from `NSLocale` instead: `languageCode`, `scriptCode`,
  `regionCode` and `currencyCode`, which Darling's CoreFoundation backs with its own ICU-backed
  `CFLocale`. That is the same data upstream reads, reached through Darling's own locale machinery.
  Two behavioural differences follow, and neither invents a value:
  - `Locale.region` reads `NSLocaleCountryCode`, so an `rg` override in the identifier is honoured
    only as far as Darling's `CFLocale` honours it. Upstream distinguishes `Locale.region` from
    `Locale.language.region` on exactly that key.
  - `Locale.Language.languageCode` returns the stored `components.languageCode` with no fallback.
    Upstream falls back to `uloc_getLanguage(components.identifier)` when the stored code is nil.
    Every `Locale.Language` initializer this overlay ships stores the code directly, so there is no
    identifier left to parse and the stored value is the complete answer; nil means the language
    genuinely has no code.
- **`Locale.numberingSystem`, `Locale.Language(identifier:)`, `Locale.Language.Components(identifier:)`,
  `Locale.Language.characterDirection` and `Locale.Language.maximalIdentifier` are ported from
  upstream** (`Locale+Components_ICU.swift`, `Locale_ICU.swift`) into `Locale+Darling.swift`. They
  make the same ICU calls upstream makes (`unumsys_open`, `uloc_getLanguage`/`Script`/`Country`,
  `uloc_getCharacterOrientation`, `uloc_addLikelySubtags`, `uloc_toLanguageTag`), against Darling's
  own ICU 66 through the `_FoundationICU` module in `shims/overlay-shims.modulemap`, which admits
  only the ICU headers these calls need; `build.sh` links `libicucore`. OpenSwiftUI uses all five.
- **`Locale.Language.script` and `Locale.Language.region` are not provided.** They are the other two
  members of the same upstream ICU file. Nothing in the app corpus binds them, and adding them would
  be more Darling reimplementation for no measured demand.

## ICU-backed format styles

`Date.FormatStyle` (with `Date.FormatStyle.Attributed`, `Date.AttributedStyle` and its
`DiscreteFormatStyle` conformance), `Date.VerbatimFormatStyle`, `Date.ParseStrategy`,
`Date.RelativeFormatStyle` and `Date.AnchoredRelativeFormatStyle` are built from swift-foundation's
`FoundationInternationalization`, over the ICU Darling already ships, and
`Date.ComponentsFormatStyle` is written over the same ICU (below).

- **The fetched files import the same `_FoundationICU` module as the `Locale` accessors above.**
  Upstream's sources `internal import _FoundationICU`, swift-foundation-icu's vendored ICU 74; here
  that name is Darling's ICU 66.1 (`shims/FoundationICU.h`), so they compile unmodified. The headers
  they call into are admitted alongside `uloc.h` and `unumsys.h`. Every call the fetched date files
  make exists in ICU 66, `udat_formatForFields` and `udat_patternCharToDateFormatField` included.
- **Fetched unmodified**: the whole `UPSTREAM_INTL_FILES` list in `build.sh` (the date, number,
  byte-count and duration styles and their ICU plumbing), plus `FoundationEssentials`'
  `Formatting/FormatterCache.swift`, `Formatting/BinaryInteger+NumericStringRepresentation.swift`
  and `String/BidirectionalCollection.swift`. `NumberFormatStyleConfiguration.swift` is fetched
  whole, so it now supplies `FormatStyleCapitalizationContext`, which had been kept separately.
- **Five override files, each a departure from the patch rule** (lines the repository carries,
  counted as above; the patch column is raw `diff -u`):

  | file | patch | file | smaller |
  |---|---|---|---|
  | `ICU+Enums.swift` | 27 lines | 253 lines | patch |
  | `ICUPatternGenerator.swift` | 41 lines | 103 lines | patch |
  | `Decimal+FormatStyle.swift` | 20 lines | 456 lines | patch |
  | `Decimal+ParseStrategy.swift` | 29 lines | 151 lines | patch |
  | `Duration+UnitsFormatStyle.swift` | 54 lines | 789 lines | patch |

  All are kept as override files for the one-mechanism reason given for the override files above.
  `ICU+Enums.swift` drops the aliases for `UDAT_NARROW_QUARTERS`, `UDAT_STANDALONE_NARROW_QUARTERS`
  (ICU 70) and `UDateFormatHourCycle` (ICU 67). `ICUPatternGenerator.swift` replaces
  `defaultHourCycle`, which calls `udatpg_getDefaultHourCycle` (ICU 67), with the hour field in the
  pattern skeleton `j` resolves to. CLDR defines `j` as the locale's preferred hour format, which is
  the datum that call reports.
  The two `Decimal` files name the `FoundationEssentials` module in their non-framework branches;
  here they name `Foundation`, the module they build into. `Duration+UnitsFormatStyle.swift`
  stores its width as an internal copy of the `Measurement<UnitDuration>.FormatStyle.UnitWidth`
  value swift-foundation's stub declares, since this overlay has no `Measurement` and the macOS
  `Measurement.FormatStyle` is not open source; and its attributed format finds the `{0}`
  placeholder with `BidirectionalCollection._range(of:anchored:backwards:)`, because
  `AttributedString.range(of:options:)` is omitted here (above).
- **`Decimal` is VibeDarling/darling-swift#63's**, `NSDecimal` imported as `Decimal` through
  darling-foundation#58's API notes. The number styles only need it to spell rounding increments
  and scales in ICU skeletons (percent formatting and `.increment` precision), and at run time
  those need darling-foundation#57's `NSDecimalString`; without it they crash in Darling's
  float-based fallback.
- **`Foundation/FormattingSupport.swift` is written for Darling.** The fetched files reach into
  internals of swift-foundation's own `Locale` and `Calendar`, which this overlay's `NSLocale`- and
  `NSCalendar`-backed types do not have. It supplies them under the same names, copying upstream
  wherever upstream's code does not depend on those internals, and marks each copied piece with its
  source file. The differences in behaviour:
  - `Locale.identifierCapturingPreferences` is the identifier and `forceFirstWeekday` is `nil`:
    Darling's `Locale` carries no per-user preference overrides, so there are none to capture.
  - `Calendar.localeIdentifierWithCalendar` canonicalizes the identifier with `uloc_canonicalize`
    (which folds a BCP 47 `-u-ca-` extension into keywords) and sets the `calendar` keyword with
    `uloc_setKeywordValue`, where upstream round-trips through `Locale.Components`, excluded here.
  - `Calendar.ComponentSet` keeps upstream's bits except `isLeapMonth` and `isRepeatedDay`, which
    nothing uses. This overlay's `Calendar.Component` has no `dayOfYear`, so a day-of-year field
    gets no update schedule; upstream's `UpdateSchedule.reduce` drops it the same way.
  - `Locale.hourCycle` (public, macOS 13) consults an `hours` keyword, then an `rg` region
    override, then the locale's own data, in the order upstream's `Locale_ICU` does. Without `rg`,
    upstream asks for the locale's region and this asks for the locale; ICU resolves `j` by region.
  - `Date.formatted(_:)` and the two `Date(_:strategy:)` initializers are upstream's
    `Date+FormatStyle.swift`, whose non-framework branch names the `FoundationEssentials` module.
  - ICU failures are logged through `os_log`; upstream calls an interpolating `Logger.error` that
    Darling's `os` overlay does not have.
- **`Foundation/Date+ComponentsFormatStyle.swift` is written for Darling.** swift-foundation ships
  only a stub of `Date.ComponentsFormatStyle` off-Darwin (`Date+ComponentsFormatStyle+Stub.swift`,
  whose `Field` is kept verbatim); the macOS implementation is not open source. The rest follows
  the SDK's `Foundation.swiftinterface` and Apple's published documentation
  (<https://developer.apple.com/documentation/foundation/date/componentsformatstyle>), over Apple ICU's
  `uameasfmt` measure formatter, which gives the styles their unit names and list patterns:
  `wide`, `abbreviated`, `condensedAbbreviated` and `narrow` are its `WIDE`, `SHORT`, `SHORTER` and
  `NARROW` widths; `spellOut` formats each value with ICU's spell-out rules and joins them with the
  locale's unit list pattern; `timeDuration` is its positional `NUMERIC` width over hours, minutes
  and seconds, leading zero fields dropped and at least two kept. The components come from
  `Calendar.dateComponents(_:from:to:)`, zero values dropped as the documentation says (a zero
  duration shows the smallest field). Where the documentation is silent these are Darling's
  choices, not observed macOS behaviour: `fields == nil` means all seven fields, the default
  `allowedUnits` of `NSDateComponentsFormatter`; `fields == []` formats as an empty string;
  `isPositive == false` formats the negative components as ICU renders them (for `timeDuration`
  ICU falls back from positional to a unit list, since it takes no negative positional values).
  The `DiscreteFormatStyle` bounds are found by stepping the moving end one smallest-field unit
  and bisecting to where the components change, to within a millisecond, the resolution at which
  CFCalendar compares dates; month and year clamping rule out inverting the calendar arithmetic.
  Week counts are always 0 under Darling today, a CoreFoundation bug tracked in
  VibeDarling/darling#858, so with automatic fields ten days read "10 days" rather than a week and
  three days.
- **Known divergence: zero integer digits.** `.precision(.integerLength(0))` (or an integer range
  of `0...0`) asks ICU for the `integer-width/*` skeleton. ICU 66's skeleton parser has no option
  that truncates every integer digit, so such a style falls back to upstream's unformatted
  description of the value, and a `Duration.UnitsFormatStyle` with a value length of 0 traps on
  upstream's force-unwrapped formatter.
- **Known divergence: CLDR data.** ICU 66 carries CLDR 36. Output follows that data, so for example
  en_US puts a plain space before the day period, where CLDR 42 and later use U+202F.

## ISO 8601 format styles

`Date.ISO8601FormatStyle` (`Date.ISO8601Format()`, `.iso8601`, the parse strategy and the
`iso8601`, `iso8601WithTimeZone` and `iso8601Date` regex components) and
`DateComponents.ISO8601FormatStyle` come from swift-foundation's `FoundationEssentials`, which
formats and parses them in Swift without ICU.

- **Fetched unmodified**: `Formatting/Date+ISO8601FormatStyle.swift`,
  `Formatting/FormatParsingUtilities.swift` and the byte-buffer types they parse and format with,
  `JSON/BufferView.swift`, `JSON/BufferViewIndex.swift`, `JSON/BufferViewIterator.swift` and
  `OutputBuffer.swift`. `FormattingSupport.swift` no longer carries its own copy of `parseError`,
  which now comes from `FormatParsingUtilities.swift`.
- **`Foundation/DateComponents+ISO8601FormatStyle.swift` is an override file**, another departure
  from the patch rule (a 12-line `diff -u` against an 821-line file), kept for the one-mechanism
  reason above. Its one change: parsing an ordinal date checks the day against `1..<367`, the
  Gregorian range upstream reads from `maximumRange(of: .dayOfYear)`, because this overlay's
  `Calendar.Component` has no `dayOfYear` case.
- **Day of year.** This overlay's `DateComponents` has no public `dayOfYear` (macOS 15). It gets an
  internal stored one, which the ISO 8601 styles read and write and which takes part in equality;
  `Calendar.date(from:)` resolves it as January 1st plus that many days, keeping the time of day,
  with swift-foundation's precedence (a `day`, or a `weekday` with an ordinal, week of year or week
  of month, wins), and `FormattingSupport.swift`'s `Calendar._dateComponents(_:from:)` fills it
  from `ordinality(of: .day, in: .year, for:)`. So ordinal dates (`.year().day()`) format and parse, but
  a `DateComponents` parsed from one does not show its day of year publicly and loses it when
  bridged to `NSDateComponents` or encoded.
- **`Calendar(identifier: .iso8601)`.** Darling's CoreFoundation has no ISO 8601 calendar, so this
  overlay already fell back to a Gregorian one. That fallback now also takes swift-foundation's ISO
  week rules (first weekday Monday, four days in the first week), which the week-of-year form
  depends on: without them 2021-01-01 formats as `2021-W01-05` instead of `2020-W53-05`. The
  calendar still reports `.gregorian` as its identifier.
- **`FormattingSupport.swift` supplies the other internals the fetched files call**: the raw-value
  `DateComponents` initializer (a plain memberwise one here, since this overlay's fields have no
  `NSDateComponentUndefined` to skip), and `TimeZone.fixedOffsetFromGMT`, the offset of zones named
  `GMT`, `GMT+hhmm` or `GMT-hhmm` and nil for others; those are the fixed-offset zones Darling's
  `NSTimeZone` makes. `TimeZone.gmt` (public since macOS 13) is added to `TimeZone.swift`.

## Morphology, InflectionRule and the two AttributedString attribute keys

- **`Foundation/Morphology.swift` is Darling-written, not upstream code, and exists because no
  upstream source serves this module's declarations.** Apple declares `Morphology`,
  `InflectionRule`, `AttributeScopes.FoundationAttributes.MorphologyAttribute` and
  `…InflectionRuleAttribute` in Foundation's closed Swift half: swift-foundation's own
  `FoundationAttributes.swift` writes them under `#if FOUNDATION_FRAMEWORK` (this build compiles
  without it), and the Swift stdlib overlay has never carried them. The trigger was measured, not
  guessed: `.../Xcode.app/Contents/SharedFrameworks/DVTInstrumentsUtilities.framework/…` (built for
  Mac OS X 14.0) strong-binds twelve `$s10Foundation…` names the deployed `libswiftFoundation.dylib`
  did not export, so the guest's dyld stopped at
  `Symbol not found: _$s10Foundation10MorphologyV17GrammaticalNumberO6pluralyA2EmFWC`. The twelve are
  the metadata and metadata-accessor triples for `Morphology`, `Morphology.GrammaticalNumber` and
  `InflectionRule`, the `GrammaticalNumber.plural` case, `Morphology.init()`, the `number` setter,
  `InflectionRule.init(morphology:)`, `InflectionRuleAttribute`'s `AttributedStringKey` conformance
  and metadata, and `AttributedString.inflected()`.
- **The declarations are Apple's published API for this module; the values are Apple's own open
  source.** The member set, spellings, availability and conformances are read out of the guest SDK's
  `Foundation.swiftinterface` (Xcode 26.3, `MacOSX.sdk`, x86_64). Raw values and implementations are
  taken from apple/swift-corelibs-foundation `Sources/Foundation/Morphology.swift`, the same API for
  the same module name under the same licence: `case singular = 1`, and so on for
  `GrammaticalGender` and `PartOfSpeech`, with the CLDR category strings ("one", "zero", "other",
  "two", "few", "many") in `Codable`. A `.swiftinterface` cannot supply raw values -- the printer
  drops them (`case singular = 1` prints as `case singular`), which was checked with swiftc 6.3.1
  rather than assumed -- and the values are independently corroborated by the SDK's Objective-C table
  for the same feature, `Headers/NSMorphology.h` (`NSGrammaticalNumberNotSet = 0, Singular, Zero,
  Plural, PluralTwo, PluralFew, PluralMany`), which is 1-based in exactly this order.
- **What this file deliberately does not provide, each for a measured reason.** `Morphology`'s
  macOS 14 members (`grammaticalCase`, `grammaticalPerson`, `pronounType`, `determination`,
  `definiteness`) and the macOS 15 `inflected(locale:userTermOfAddress:inflectionConcepts:)`: no
  binary in the closure demands them, and neither open source implements them for this module, so
  their `Codable` wire form would have to be guessed. `Morphology : _ObjectiveCBridgeable` and the
  whole Objective-C side: Darling's Foundation has no `NSMorphology`/`NSInflectionRule` class at all,
  so there is nothing to bridge to, and for the same reason the two `let morphology`/`let inflect`
  stored properties are not added to `AttributeScopes.FoundationAttributes` (they cannot live in an
  extension, and the scope would then enumerate attributes whose Objective-C conversion this tree
  cannot do). The macOS 14 deprecation of `CustomPronoun` in favour of `TermOfAddress` is dropped
  because this tree has no `TermOfAddress` to name.
- **`AttributedString.inflected()` answers exactly where it can and stops where it cannot.** With no
  run carrying an inflection attribute the documented answer is the receiver, and that is what it
  returns; a string that does ask for inflection hits a `fatalError` naming the missing engine
  instead of coming back uninflected, which would be a silently wrong string. The engine behind
  inflection is Darwin's closed Foundation, and Apple's own open source says the same thing where it
  can: `InflectionRule.canInflect(language:)` and `canInflectPreferredLocalization` are `false`, and
  corelibs does not ship `inflected()` at all.
- **The two keys `NSAttributedString.Key.morphology` and `.inflectionRule` are declared here** with
  the raw values corelibs uses ("NSMorphology", "NSInflect"), because the SDK's Foundation headers
  carry no such constants: the Objective-C half of the feature is not in this tree.
- **`Foundation/CocoaError.swift` gains `keyValueValidation`** (both as `CocoaError.Code` and on
  `CocoaError`, as the file already does for the other codes it carries). It is
  `NSKeyValueValidationError` (1024) from the SDK's `FoundationErrors.h`, and is what
  `Morphology.setCustomPronoun(_:forLanguage:)` reports for an unsupported language, as Apple's
  implementation does.

## DVTFoundation's four Foundation symbols (the `bytes(encoding:)` rung)

- **What the rung is.** Xcode 26.3's `Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/DVTFoundation`
  (built for Mac OS X 14.0) binds four Swift symbols of module Foundation eagerly and strongly, and the
  deployed `libswiftFoundation.dylib` exported none of them, so the guest's dyld stopped at the first
  in the image's bind order:
  `Symbol not found: _$sSS10FoundationE5bytes8encodingSSSgxh_SSAAE8EncodingVtcSTRzs5UInt8V7ElementRtzlufC`,
  `Referenced from: .../SharedFrameworks/DVTFoundation.framework/Versions/A/DVTFoundation` (built for
  Mac OS X 14.0), `Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`
  [measured 2026-10-12]. All four are declarations the release/5.4 Darwin overlay carries and the
  reduction in this directory dropped, so nothing here is invented: three of the four files that
  carried them are the same upstream files the surrounding entries already come from.
- **`String.init?(bytes:encoding:)`** — `_$sSS10FoundationE5bytes…lufC`, i.e.
  `(extension in Foundation): Swift.String.init?<A where A: Sequence, A.Element == UInt8>(bytes: __shared A, encoding: String.Encoding) -> String?`.
  Declaration: the guest SDK's `Foundation.swiftinterface` line 15517 (inside
  `@available(macOS 10.10, …) extension Swift.String`). Body: **verbatim** from release/5.4
  `stdlib/public/Darwin/Foundation/NSStringAPI.swift:209` (the file this entry's `Foundation/NSStringAPI.swift`
  is already built from; the same body is in corelibs `Sources/Foundation/NSStringAPI.swift:257`) — a
  real implementation: a `String._tryFromUTF8` fast path for `.utf8` and otherwise
  `-[NSString initWithBytes:length:encoding:]`, which is `CFStringCreateWithBytes(…, isExternalRepresentation: true)`
  (src/external/foundation/src/NSString.m:434) and returns nil for bytes invalid in the encoding.
  The only change from upstream is the doc comment's "ecoding" typo.
- **`NSExpression.init<Root, Value>(forKeyPath:)`** — `_$sSo12NSExpressionC10FoundationE10forKeyPath…lufC`.
  Declaration: `Foundation.swiftinterface` line 20014. Body: **verbatim** from release/5.4
  `stdlib/public/Darwin/Foundation/NSExpression.swift:25`:
  `self.init(forKeyPath: _bridgeKeyPathToString(keyPath))`. A real implementation on top of Darling's
  `+[NSExpression expressionForKeyPath:]` (src/external/foundation/src/NSExpression.m:62, which builds a
  real `NSKeyPathExpression`), and the `KeyPath` -> `String` conversion is the standard library's
  `AnyKeyPath._kvcKeyPathString`, whose own comment documents it as "SPI for the Foundation overlay to
  allow interop with KVC keypath-based APIs". A key path with no KVC string is an **explicit failure,
  never a wrong value**: `_bridgeKeyPathToString` — already in this module at
  `Foundation/NSObject.swift:47`, from release/5.4 `NSObject.swift:154` — calls
  `fatalError("Could not extract a String from KeyPath \(keyPath)")`, which is Apple's own measured
  behaviour for this initializer (swift-corelibs-foundation issue #4085: `NSExpression(forKeyPath: \String.count)`
  -> `Fatal error: Could not extract a String from KeyPath Swift.KeyPath<Swift.String, Swift.Int>`).
- **`NSOrderedSet.makeIterator()`** — `_$sSo12NSOrderedSetC10FoundationE12makeIterator…yF`, returning
  `Foundation.NSFastEnumerationIterator`. Declaration: `Foundation.swiftinterface` line 17917 (inside
  `extension Foundation.NSOrderedSet : Swift.Sequence`). Body: **verbatim** from release/5.4
  `stdlib/public/Darwin/Foundation/NSSet.swift:45` (`return NSFastEnumerationIterator(self)`) — a real
  implementation: the iterator drives `-countByEnumeratingWithState:objects:count:`, which Darling's
  `NSOrderedSet` implements (src/external/corefoundation/NSOrderedSet.m:804) and which its header
  declares by conforming the class to `NSFastEnumeration`
  (src/external/foundation/include/Foundation/NSOrderedSet.h:8).
- **`NSArray.init(arrayLiteral:)`** — `_$sSo7NSArrayC10FoundationE12arrayLiteral…cfC`. Declaration:
  `Foundation.swiftinterface` line 17852 (inside `extension Foundation.NSArray : Swift.ExpressibleByArrayLiteral`).
  Body: **verbatim** from release/5.4 `stdlib/public/Darwin/Foundation/NSArray.swift:19`, the first
  extension of that file (`self.init(array: elements)`, "let bridging take care of it") — a real
  implementation through `-[NSArray initWithArray:]` (src/external/foundation/include/Foundation/NSArray.h:79).
  It lives in `Foundation/Array.swift`, the file that is this tree's remains of that upstream file, and
  the file's comment already says the conformance was dropped.
- **What the demanding image does with each (measured, not assumed).** From its bind table
  (chained-fixups decode): one bind per API, the generic/abstract entry point only — no specialization
  of any of them, and for the two conformances the image binds no conformance accessor of its own.
  From its disassembly: `bytes(encoding:)` is called once (0x33f51c) with `Foundation.Data`'s metadata
  and its `Swift.Sequence` conformance (so `S = Data` at run time) and `.utf8`, and the `String?` result
  is nil-tested immediately; `NSExpression(forKeyPath:)` once (0x2f1e5c) inside
  `NSObject.dvt_newSharedObserver<Root>(forKeyPath:observeInitial:withHandlerBlock:)`, result retained
  and sent an Objective-C message; `makeIterator()` once (0x2bc4a9), the returned iterator driven
  through the `NSFastEnumerationIterator : IteratorProtocol` conformance the image also binds; and
  `NSArray(arrayLiteral:)` once (0x2c0d60), the returned array passed straight to an Objective-C message.
- **The two conformance descriptors that come with them.** Declaring the conformances adds
  `_$sSo12NSOrderedSetCST10FoundationMc` and `_$sSo7NSArrayCs25ExpressibleByArrayLiteral10FoundationMc`
  to the export trie beside the four demanded names (measured by diffing the built trie against the
  previous copy: +6 names, 0 removed). Nothing in the closure binds either.
- **What is deliberately not here.** The rest of the upstream files these declarations come from, each
  because no image in the closure demands its symbol: `NSExpression.init(format:)` (release/5.4
  `NSExpression.swift:18`), `NSOrderedSet.init(objects:)` (release/5.4 `NSSet.swift:129`), and `NSSet`'s
  `Sequence` and literal conformances beside them (release/5.4 `NSSet.swift:36,143`). (`NSOrderedSet`'s
  own `ExpressibleByArrayLiteral` was on this list until a later rung measured it as demanded by
  IDEFoundation and added it to `NSOrderedSet.swift`; see "NSOrderedSet's literal conformance" below.)
  A grep of the coverage graph's unmet demands for
  `So12NSExpression`, `So12NSOrderedSet`, `So7NSArrayC10FoundationE` finds those names and, after this
  rung, `NSOrderedSet.arrayLiteral` as well.
  DVTFoundation's other unmet demands are not this module's: `_OBJC_CLASS_$_NSConstantDoubleNumber`,
  `_OBJC_CLASS_$_NSConstantFloatNumber` and `_OBJC_CLASS_$_NSListFormatter` are Objective-C classes of
  the Foundation framework binary, `__dyld_get_dlopen_image_header` and `_macho_arch_name_for_cpu_type`
  belong to libSystem.B, `__LSRegisterURLWithOptions` to CoreServices, and
  `_SecPolicyCreateAppleExternalDeveloperOptionalExpiry` to Security.
- **Artifact and measured result.** The four names are in the deployed export tries of both prefix
  roots; `libswiftFoundation.dylib` sha256
  `202d8cf3481b2bc2813a11c0588ff83cef235c63822708b3a3b9bd15ba81d47a` (built = payload = staged = both
  deployed copies = receipt; the trie diff against the previous copy is +6 names, 0 removed). The
  ladder run after that deploy walks past all four: both workloads' loader stop is now
  `Symbol not found: __dyld_get_dlopen_image_header` / `Referenced from: .../DVTFoundation` /
  `Expected in: /usr/lib/libSystem.B.dylib`, and no line of either log still names a
  `bytes`/`forKeyPath`/`makeIterator`/`arrayLiteral` symbol. That new stop is DVTFoundation's next
  eager demand and belongs to libSystem.B, not to this module — the first of the seven names listed
  above, which this rung deliberately did not touch.

## XCResultKit's thirteen Foundation symbols (the URLResourceValues rung)

- **What the rung is.** Xcode 26.3's `Contents/SharedFrameworks/XCResultKit.framework/Versions/A/XCResultKit`
  (built for Mac OS X 14.0) binds thirteen Swift symbols of module Foundation eagerly and strongly
  (twelve APIs plus the `.Tu` continuation thunk of the async one), and the deployed
  `libswiftFoundation.dylib` exported none of them, so the guest's dyld stopped at the first in the
  image's bind order:
  `Symbol not found: _$s10Foundation17URLResourceValuesV40volumeAvailableCapacityForImportantUsages5Int64VSgvg`,
  `Referenced from: .../SharedFrameworks/XCResultKit.framework/Versions/A/XCResultKit` (built for
  Mac OS X 14.0), `Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`
  [measured 2026-10-12]. Twelve of the thirteen are answered with real behaviour and one with an
  explicit failure; each is stated below.
- **`URLResourceValues.volumeAvailableCapacityForImportantUsage`** — `_…URLResourceValuesV40volumeAvailableCapacityForImportantUsages5Int64VSgvg`,
  i.e. `Swift.Int64?`. Declaration: the guest SDK's `Foundation.swiftinterface` line 15948 (inside
  `@available(macOS 10.13, iOS 11.0, *)` in `struct Foundation.URLResourceValues`). **Documented
  value from a real fact**: the property is `_get(URLResourceKey(rawValue: "NSURLVolumeAvailableCapacityForImportantUsageKey"))`,
  the same reduction of release/5.4 `stdlib/public/Darwin/Foundation/URL.swift:308` this file's other
  properties are. The tree answers that key with a real number: `-[NSURL resourceValuesForKeys:error:]`
  (src/external/corefoundation/NSURL.m:515) `statvfs`es the URL and returns `f_bfree * f_bsize` as a
  CFNumber, so a file URL on a reporting volume gets a real capacity and anything else (a non-file URL,
  or a failing `statvfs`) contributes no dictionary entry, which is `nil` — absence, never an invented
  capacity. The key is spelled by its raw value because `Foundation/NSURL.h` declares
  `NSURLVolumeAvailableCapacityKey` but not this newer sibling; the constant and its value are in
  NSURL.m:135, so nothing is guessed.
- **`URL.init(filePath:directoryHint:relativeTo:)`** — `_…3URLV8filePath13directoryHint10relativeTo…cfC`.
  Declaration: `Foundation.swiftinterface` line 16565 (`@available(macOS 13.0, iOS 16.0, watchOS 9.0,
  tvOS 16.0, *)`). **Real implementation**, written the way this tree's other URL initializers are: the
  `DirectoryHint` switch takes `.isDirectory` as a directory, `.notDirectory` as a file, and — as
  `DirectoryHint`'s own comment in `URL.swift` already documents for this tree — `.inferFromPath` and
  `.checkFileSystem` from a trailing `/`; a relative path is resolved against `base` through
  `+[NSURL fileURLWithPath:isDirectory:relativeToURL:]`, which is what the sibling
  `init(fileURLWithPath:relativeTo:)` already uses.
- **`URL.appending(queryItems:)`** — `_…3URLV9appending10queryItemsACSayAA12URLQueryItemVG_tF`.
  Declaration: `Foundation.swiftinterface` line 16576. Body: **verbatim** from swift-foundation
  `Sources/FoundationEssentials/URL/URL.swift:1514` (the modern open source that carries this
  macOS 13 API; release/5.4 predates it), over this tree's `URLComponents`:
  `URLComponents(url:resolvingAgainstBaseURL:)`, append to `queryItems`, `components.url ?? self`.
  Real: `URLQueryItem` and that accessor are already in `Foundation/URLComponents.swift`.
- **`String.init?(bytesNoCopy:length:encoding:freeWhenDone:)`** — `_…SS10FoundationE11bytesNoCopy…SSSgSv_SiSSAAE8EncodingVSbtcfC`.
  Declaration: `Foundation.swiftinterface` line 22572 (deprecated: macOS 13), reproduced with that
  availability. Body: **verbatim** from release/5.4 `stdlib/public/Darwin/Foundation/NSStringAPI.swift:239`
  (the same body corelibs `Sources/Foundation/NSStringAPI.swift` carries). Real: over
  `-[NSString initWithBytesNoCopy:length:encoding:freeWhenDone:]`
  (src/external/foundation/src/NSString.m:484), returning `nil` for bytes invalid in the encoding.
- **`String.init(utf16CodeUnits:count:)`** — `_…SS10FoundationE14utf16CodeUnits5count…cfC`. Declaration:
  `Foundation.swiftinterface` line 22574. Body: **verbatim** from release/5.4 `NSStringAPI.swift:257`.
  Real: over `+[NSString stringWithCharacters:length:]` / `-initWithCharacters:length:` (NSString.m:498).
- **`NSDictionary : Sequence`** — `_…So12NSDictionaryC10FoundationE12makeIteratorAbCE0D0CyF` and
  `_…E8IteratorC4nextyp3key_yp5valuetSgyF`. Declarations: `Foundation.swiftinterface` lines 21520 and
  21509. Bodies: **verbatim** from release/5.4 `stdlib/public/Darwin/Foundation/NSDictionary.swift`
  (`makeIterator` and the `Iterator` class, whose `next()` is `object(forKey:)` on the key the fast
  enumerator yielded). Real: the iterator drives `countByEnumeratingWithState:objects:count:` through
  this tree's `NSFastEnumerationIterator` (`Foundation/NSFastEnumeration.swift`). They live in
  `Foundation/NSDictionary+Literal.swift`, the file that is this tree's remains of that upstream file.
- **`FileHandle.read(upToCount:)`** and **`FileHandle.seekToEnd()`** — `_…So12NSFileHandleC10FoundationE4read9upToCountAC4DataVSgSi_tKF`
  and `_…E9seekToEnds6UInt64VyKF`. Declarations: `Foundation.swiftinterface` lines 490 and 496. Bodies
  follow corelibs `Sources/Foundation/FileHandle.swift:494,537` (`_readDataOfLength(_:untilEOF:)` /
  `lseek(_fd, 0, SEEK_END)`), over the descriptor the class's own Objective-C surface reports, exactly
  as the sibling `write(contentsOf:)` already does. Real: reads and seeks the descriptor, retries
  `EINTR`, returns `nil` at end of file, and throws a `_FileHandleReadError` — the read half of
  `_NSErrorWithErrno(_:reading: true)` — on a failing errno. `readToEnd()` was added later, by the
  XCTHarness rung (see "XCTHarness's four Foundation symbols" below); `offset()` is still not here,
  because no image in this closure binds it.
- **`StringProtocol.localizedCompare(_:)`** and **`StringProtocol.write(toFile:atomically:encoding:)`** —
  `_…Sy10FoundationE16localizedCompare…lF` and `_…Sy10FoundationE5write6toFile…lF`. Declarations:
  `Foundation.swiftinterface` lines 22708 and 15526. Bodies: **verbatim** from release/5.4
  `NSStringAPI.swift:907,1192` (`_ns.localizedCompare(_:)` / `_ns.write(toFile:atomically:encoding:)`),
  with the generic argument converted by `String(_:)` where upstream uses its internal
  `_ephemeralString`. Real: over `-[NSString localizedCompare:]` (src/external/foundation/include/Foundation/NSString.h:127)
  and `-[NSString writeToFile:atomically:encoding:error:]` (NSString.h:191).
- **`URLSession.data(for:delegate:)`** — `_…So12NSURLSessionC10FoundationE4data3for8delegate…YaKF` and
  its `.Tu` thunk. Declaration: `Foundation.swiftinterface` line 19828 (`@available(macOS 12.0, iOS 15.0,
  watchOS 8.0, tvOS 15.0, *)`). **Explicit failure**: this tree has no `URLSession` to serve it with.
  The deployed Foundation.framework itself only *imports* `_OBJC_CLASS_$_NSURLSession` (indirect) and no
  image in the prefix defines it [measured: a scan of the prefix's dylibs finds no definition], and no
  open source carries the async API for this module either (swift-corelibs-foundation's
  `FoundationNetworking` has `URLSession` and its task APIs but neither `data(for:delegate:)` nor
  `data(from:delegate:)`; swift-foundation has no `URLSession`). The declaration therefore lives in
  `Foundation/URLSession.swift` and throws `NSFeatureUnsupportedError` (3328) in the Cocoa error domain
  with a description naming the missing class: the loader resolves the symbol, and a caller gets an
  error it can handle rather than an invented response. Measured: declaring it adds **no** reference to
  `_OBJC_CLASS_$_NSURLSession` to the dylib (the extension needs the class's name, not its object), and
  its two names are exported.
- **What the demanding image does with each (measured, not assumed).** Thirteen eager strong binds, one
  per API, all with dependency field `/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`
  and ordinal 1 — the generic entry point only, no specializations. From its disassembly, one call site
  each (six for `appending(queryItems:)`, twenty-one for `init(filePath:…)`, five for `bytesNoCopy`,
  six for `localizedCompare`, two for the iterator's `next()`), e.g.
  `volumeAvailableCapacityForImportantUsage` at 0x2ef4d2 inside
  `XCResultStorage.CompressingCASDatabase.getAvailableDiskSpace()`, `init(filePath:directoryHint:relativeTo:)`
  at 0x325e43 inside the `ResultBundle.getRuntimeWarnings()` sort, `appending(queryItems:)` at 0x4ab689
  inside `ResultDataPublisher.URLSessionWriter.writeAttachment(data:)`, `read(upToCount:)` at 0x5c3b1e
  inside `DataViewer.Handler.getAttachment(input:)`, `seekToEnd()` at 0x5b0afb inside
  `DataController.MessageStore.appendToEventStream(_:)`, the `NSDictionary` iteration at 0x2369ef/0x236a05
  inside `MinimalTSCBasic.JSON.convertToJSON(_:)`, `localizedCompare` at 0x543dd1 inside
  `HTTPTypes.HTTPFields.prettyDescription`, and `data(for:delegate:)` tail-called (`jmp`) at 0x4ab795
  and five more.
- **What is deliberately not here.** `URLResourceValues`'s other volume properties, `appending`'s
  sibling `append(queryItems:)`, `String.init(utf16CodeUnitsNoCopy:)`, `NSDictionary`'s bridging
  subscript and `NSMutableDictionary`'s override, and `URLSession.data(from:delegate:)`: no image in
  this closure binds any of them (a grep of the coverage graph's unmet demands finds none).
- **Artifact and measured result.** The thirteen names are in the deployed export tries of both prefix
  roots; `libswiftFoundation.dylib` sha256 `5dc66fcd640f2e826e368abd52a77cb31ebcbabba9b27d05e386d85fd0c2a23f`
  (built = payload = staged = both deployed copies = receipt). The trie diff against the previous copy
  is +40 names (the thirteen plus the `CocoaError` read codes, the `NSDictionary.Iterator` metadata and
  the `NSDictionary : Sequence` conformance descriptor), 0 removed.

## XCTHarness's four Foundation symbols (the NSSet/readToEnd rung)

- **What the rung is.** Xcode 26.3's `Contents/SharedFrameworks/XCTHarness.framework/Versions/A/XCTHarness`
  binds four Foundation Swift names eagerly and strongly (chained-fixups imports[534], [539], [540], [541];
  `lib_ordinal` 12 = Foundation; `weak_import = 0`). Three of them are NSSet's and one is FileHandle's:
  `_$sSo5NSSetC10FoundationE12arrayLiteralABypd_tcfC`, `_…E12makeIteratorAC017NSFastEnumerationD0VyF`,
  `_…E3setA2Bh_tcfC` and `_$sSo12NSFileHandleC10FoundationE9readToEndAC4DataVSgyKF`, the last of which
  is the name this rung answers for (the wave's coverage-graph prediction for this rung). The same
  names are demanded by other images of the closure: `arrayLiteral` also by DVTSourceControl and
  IDEFoundation, `makeIterator` also by IDEFoundation, `readToEnd` also by AppThinning. A grep of the
  coverage graph's unmet demands for `So5NSSetC10FoundationE` and `So12NSFileHandleC10FoundationE` finds
  these four and nothing else.
- **`FileHandle.readToEnd()`** — declaration: `Foundation.swiftinterface` line 486
  (`@available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *)`, `public func readToEnd() throws ->
  Foundation.Data?`). Body: **Apple's own composition** — corelibs `Sources/Foundation/FileHandle.swift:487`
  is `guard self != FileHandle._nulldeviceFileHandle else { return nil }; return try read(upToCount:
  Int.max)`, and both halves are already what this file's `read(upToCount:)` answers for this class (nil for
  a negative descriptor, read to end of file with a 64 KiB buffer). It sits in
  `Foundation/NSFileHandle.swift` beside `write(contentsOf:)`, `read(upToCount:)` and `seekToEnd()`.
  Real: it reads the descriptor to end of file and throws a `FileHandle` read `NSError` on a failing errno.
- **`NSSet.makeIterator()`** — `_$sSo5NSSetC10FoundationE12makeIteratorAC017NSFastEnumerationD0VyF`,
  returning `Foundation.NSFastEnumerationIterator`. Declaration: `Foundation.swiftinterface` line 17906
  (inside `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *) extension Foundation.NSSet :
  Swift.Sequence`). Body: **verbatim** from the corelibs Darwin overlay file that is IN THIS TREE,
  `src/external/corefoundation/submodules/swift-corelibs-foundation/Darwin/Foundation-swiftoverlay/NSSet.swift:37`
  (`return NSFastEnumerationIterator(self)`) — a real implementation: the iterator drives
  `-countByEnumeratingWithState:objects:count:`, which Darling's NSSet implements
  (src/external/corefoundation/NSSet.m) and which its header declares by conforming the class to
  `NSFastEnumeration` (src/external/foundation/include/Foundation/NSSet.h:6, and implemented at
  src/external/corefoundation/NSSet.m:71).
- **`NSSet.init(arrayLiteral:)`** — `_$sSo5NSSetC10FoundationE12arrayLiteralABypd_tcfC`. Declaration:
  `Foundation.swiftinterface` lines 17957-17962 (`required convenience public init(arrayLiteral elements:
  Any...)` in `extension Foundation.NSSet : Swift.ExpressibleByArrayLiteral`). Body: **verbatim** from the
  same in-tree file, line 135 (`self.init(array: elements)`), i.e. through `-[NSSet initWithArray:]`
  (src/external/foundation/include/Foundation/NSSet.h:50).
- **`NSSet.init(set:)`** — `_$sSo5NSSetC10FoundationE3setA2Bh_tcfC`. Declaration: `Foundation.swiftinterface`
  lines 17969-17971 (`@nonobjc convenience public init(set anSet: __shared Foundation.NSSet)`). Body:
  **verbatim** from the same in-tree file, lines 143-179: `CFSetGetValues` into a raw buffer of unretained
  pointers, then `self.init(objects:count:)`, which retains them. Real: `CFSetGetValues` is Darling
  CoreFoundation's own (src/external/corefoundation/CFSet.c:474, exported by the deployed
  CoreFoundation) and `-initWithObjects:count:` is implemented at
  src/external/corefoundation/NSSet.m:270. Two mechanical adaptations were needed for Darling's imports
  and both are measured with `swiftc -frontend -typecheck` against Darling's SDK, not guessed:
  `- (NSUInteger)count;` imports as the METHOD `count()` (upstream's `anSet.count` becomes `anSet.count()`),
  and `- (id)initWithObjects:(const id [])objects count:(NSUInteger)cnt;` imports with OPTIONAL elements
  (`UnsafePointer<AnyObject?>`, as the NSDictionary literal precedent already records), so upstream's
  `assumingMemoryBound(to: AnyObject.self)` becomes `AnyObject?.self`. The declarations live in a new
  `Foundation/NSSet.swift`, the sibling of `NSOrderedSet.swift` and `NSDictionary+Literal.swift`, each of
  which is one class's remains of release/5.4's `NSSet.swift`/`NSDictionary.swift`.
- **What the demanding image does with each (measured, not assumed).** From XCTHarness's own bind table:
  four eager strong binds in the Foundation field, the plain entry point of each API, no specialization.
  From its disassembly: `makeIterator()` has four call sites (0xc40ab, 0xc433c, 0xc4431, 0xc45f5), all
  inside stdlib Sequence algorithms the client's binary SPECIALIZED for NSSet
  (`Sequence.compactMap`/`forEach`/`contains(where:)`/`first(where:)`, mangled `_$sSTsE…So5NSSetC_Tg5…`),
  and the returned iterator is then driven by `Sequence.next()` (0xc4110) through the conformance accessor
  `_$s10Foundation25NSFastEnumerationIteratorVStAAMc` (0xc40b7), the loop ending where `next()` answers an
  empty Optional (0xc4115) — so the conformance must really walk the set; `init(arrayLiteral:)` twice
  (0xc6c95, 0x15e29b), rdi = the `_ContiguousArrayStorage<Any>` of the literal (0xc6c52), and the +1
  result is passed on as an Objective-C message argument (0xc6caa) and released (0xc6cb5);
  `init(set:)` once (0xc4c50) in `XCTHGenericRunDestinationPool.init(runDestinations:)` with rdi = the
  argument the client retains at 0xc4c44, the result stored straight into the object's
  `availableRunDestinations` ivar (0xc4c55) with no further retain; `readToEnd()` once (0x93f44) inside
  the NSTask-terminationHandler closure of `invokeXCRun`, whose result is decoded as UTF-8
  (`Data.withContiguousStorageIfAvailable` + `String(decoding:as:UTF8)`, 0x94036) and destroyed by the
  caller (`Data.SgWOe`, 0x94050), with the closure's own throw path for a failing errno (0x93ef4).
- **The two conformance descriptors that come with them.** Declaring the two conformances adds
  `_$sSo5NSSetCST10FoundationMc` and `_$sSo5NSSetCs25ExpressibleByArrayLiteral10FoundationMc` to the export
  trie beside the four demanded names (measured by diffing the built trie against the previous copy:
  **+6 names, 0 removed**). Nothing in the closure binds either — XCTHarness calls the NSSet algorithms
  through specializations, not through the conformance.
- **What is deliberately not here.** `NSSet.init(objects:)` and `NSSet : CustomReflectable` with its
  `customMirror`, both of which the in-tree corelibs file carries and nothing in this closure binds. The
  `NSSet`/`NSOrderedSet` halves of that file are split by class here, so `NSOrderedSet`'s own
  `init(objects:)` stays in `NSOrderedSet.swift`; `NSOrderedSet.arrayLiteral` is also demanded (by
  IDEFoundation in this closure, and DVTSourceControl in the tree), and a later rung added it there —
  see "NSOrderedSet's literal conformance" below. And `FileHandle.offset()`, which Apple declares beside
  `readToEnd()`: no image in this closure binds it.
- **Artifact and measured result.** The four names are in the deployed export tries of **both** prefix
  roots (`usr/lib/swift/…` and `libexec/darling/usr/lib/swift/…`; the dylib is x86_64-only, so there is no
  second slice to check); `libswiftFoundation.dylib` sha256
  `5cf19386b29c182547f96526c56ecda115521f2d513f169a4e29f5dd4adf8726` (built = payload = staged = both
  deployed copies = receipt; the bootstrap's own guest smoke passed and the receipt validates). The ladder
  run after that deploy walks past all four: both workloads' loader stop is now
  `Symbol not found: __LSOpenURLsWithCompletionHandler` / `Referenced from: .../XCTHarness` /
  `Expected in: /System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices`, and neither
  of this run's harness logs, nor the minproj guest log read back after the run, names a
  `readToEnd`/`So5NSSetC10FoundationE` symbol (0 hits). That new stop is XCTHarness's next eager demand
  and belongs to CoreServices, not to this module.

## NSOrderedSet's literal conformance, and Foundation's `NSMultipleUnderlyingErrorsKey` (the Foundation-errors rung)

Two more Foundation names the ladder demanded next, one per mechanism. Both are read off the coverage
graph over the guest's own run log (`--entry private/var/tmp/xcodebuild-minproj.out`), in whose unmet
list the field `/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation` carries 54
distinct names across the closure; these two are the next eager demands on the loader's path and the
rung's.

- **`NSOrderedSet.init(arrayLiteral:)` -- this module, the NSSet precedent one class over.**
  `_$sSo12NSOrderedSetC10FoundationE12arrayLiteralABypd_tcfC`, bound eagerly and strongly
  (chained-fixups imports[1666], lib_ordinal 27 = Foundation, weak_import 0) by
  `Contents/Frameworks/IDEFoundation.framework/Versions/A/IDEFoundation`; DVTSourceControl binds it too
  (it is not reached in this run's closure, and the NSSet/readToEnd rung reported it by name).
  **Declaration:** `Foundation.swiftinterface` line 17963-17967 (`extension Foundation.NSOrderedSet :
  Swift.ExpressibleByArrayLiteral { required convenience public init(arrayLiteral elements: Any...);
  public typealias ArrayLiteralElement = Any }`). **Body:** **verbatim** from release/5.4 `NSSet.swift`
  line 149 (`self.init(array: elements)`), where `init(array:)` is Darling's
  `-[NSOrderedSet initWithArray:]` (src/external/corefoundation/NSOrderedSet.m, deployed) -- a real
  ordered set of the elements, not a stub. `self.init(array: elements)` was type-checked against
  Darling's SDK before the build (the rung's `probe-orderedset.swift`). It lives in
  `Foundation/NSOrderedSet.swift`, beside the `makeIterator()` a previous rung put there.
  **Measured client use:** IDEFoundation 0x72e3fd, the symbol's only `callq` in the x86_64 slice --
  `rdi = __swiftEmptyArrayStorage` (the literal is `teams: NSOrderedSet = []`) and the +1 result is
  stored straight into the object's `teams` ivar (0x72e402) with no further retain.
  **Comes with it:** declaring the conformance also adds
  `_$sSo12NSOrderedSetCs25ExpressibleByArrayLiteral10FoundationMc`; nothing in the closure binds it.

- **`NSMultipleUnderlyingErrorsKey` -- not this module: a real constant in CoreFoundation.**
  `_NSMultipleUnderlyingErrorsKey`, bound eagerly and strongly by XCTHarness (imports[565], lib_ordinal
  12) and IDEFoundation (imports[1747], lib_ordinal 27). The demand's own blame text names the
  Foundation ordinal, but the tree's error-constant convention puts the NS\*ErrorKey constants in
  **CoreFoundation**, which `Foundation.framework` re-exports (`LC_REEXPORT_DYLIB`): the sibling
  `NSUnderlyingErrorKey` is defined at `src/external/corefoundation/NSError.m:24` and exported by the
  deployed CoreFoundation (measured). This constant is added beside it there, and declared beside it in
  `src/external/foundation/include/Foundation/NSError.h`.
  **Measured client use** (both demanding images, x86_64 slices): the symbol is loaded and
  **dereferenced** (`movq <sym>(%rip), %rax; movq (%rax), %rax`) and the value is used as an NSError
  userInfo dictionary key -- XCTHarness 0xce63 into a 4-key stack buffer beside
  `NSLocalizedDescriptionKey`/`NSUnderlyingErrorKey`, IDEFoundation 0xfa33a into the keys array of a
  4-key `dictionaryWithObjects:forKeys:count:`, and XCTHarness 0x15024b bridges it to a Swift String
  key. So it is a DATA symbol whose **value** is read and used by content (not by pointer identity),
  and a real constant `NSString` is required.
  **Value -- measured, not assumed:** unlike every other NS\*ErrorKey in that file, this one's value
  keeps its "Key" suffix: `@"NSMultipleUnderlyingErrorsKey"`. Apple prints userInfo keys verbatim in
  NSError descriptions, and a real-device log reads `UserInfo={NSMultipleUnderlyingErrorsKey=( ... )}`
  (Apple Developer Forums thread 815631); swift-foundation's own reader of this key hardcodes the same
  literal. The name-minus-"Key" guess would have been a plausible wrong value.

- **Artifact and measured result.** CoreFoundation sha256
  `4234b8722b1988330da93b1a7042c3cd10c6bedbe37e9334bbd6b992026f7acc` (universal i386+x86_64; built =
  **both** deployed prefix roots = receipt), and `libswiftFoundation.dylib` sha256
  `58c8aa092fd10cf7b0b31ebf64039b1da7c94fdc667883d2b85b07890cb85e49` (x86_64-only; built = payload =
  staged = **both** deployed prefix roots = receipt; the trie diff against the previous copy is **+2
  names, 0 removed** -- `arrayLiteral` and the literal conformance descriptor). The bootstrap's guest
  smoke passed and the receipt validates. The ladder run after the deploy walks past both names: both
  workloads' loader stop is now
  `Symbol not found: _CONTAINER_PERSONA_PRIMARY` / `Referenced from: .../XCTHarness` /
  `Expected in: /usr/lib/libSystem.B.dylib`, and neither harness log nor either guest log names
  `NSMultipleUnderlyingErrorsKey`/`So12NSOrderedSetC10FoundationE` (0 hits). That new stop belongs to
  libSystem.B, not to these components.

## Notarization's `URLResourceValues.preferredIOBlockSize` (the preferred-IO-block-size rung)

The Foundation-field name the loader stops on next. Read off the coverage graph over the guest's own
run log (`--entry private/var/tmp/xcodebuild-minproj.out`), whose unmet list carries the field
`/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation` with 52 distinct names across
the closure; this one is the sole Foundation-field demand on the loader's path (sequence #3, after
the two `flat-lookup` entries that are Apple-provided and do not stop anything), and the other 51 sit
behind 159 non-Foundation stops that belong to other components.

- **What the rung is.** Xcode 26.3's `Contents/SharedFrameworks/Notarization.framework/Versions/A/Notarization`
  (built for Mac OS X 14.0) binds `_$s10Foundation17URLResourceValuesV20preferredIOBlockSizeSiSgvg`
  eagerly and strongly -- chained-fixups imports[107], lib_ordinal 6 = Foundation, weak_import 0 --
  and the deployed `libswiftFoundation.dylib` did not export it, so dyld stopped with
  `Symbol not found: _$s10Foundation17URLResourceValuesV20preferredIOBlockSizeSiSgvg` /
  `Referenced from: .../SharedFrameworks/Notarization.framework/Versions/A/Notarization` /
  `Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation` [measured
  2026-10-12].
- **Declaration** -- the guest SDK's `Foundation.swiftinterface` line 15815 (inside
  `public struct Foundation.URLResourceValues`, which begins at line 15651): `public var
  preferredIOBlockSize: Swift.Int? { get }`, i.e. `Swift.Int?`.
- **Body -- the same accessor as every other property in this file.** `_get(.preferredIOBlockSizeKey)`,
  verbatim from release/5.4 `stdlib/public/Darwin/Foundation/URL.swift:215`, which is what the sibling
  `creationDate`/`fileSize` already are. **Real fact, not a plausible value**: the tree answers
  `NSURLPreferredIOBlockSizeKey` from `stat`'s `st_blksize` in
  `-[NSURL resourceValuesForKeys:error:]` (src/external/corefoundation/NSURL.m:441-449), and it is a
  key the tree declares and exports (`src/external/foundation/include/Foundation/NSURL.h:38`,
  `NSURLPreferredIOBlockSizeKey`), unlike the newer volume-capacity sibling whose header is missing. A
  resource whose block size cannot be interrogated (a non-file URL, or a `stat` failure) contributes no
  dictionary entry, which is `nil` -- absence, never an invented size.
- **Measured client use (x86_64 slice, not assumed).** Notarization imports the key *constant*
  `_NSURLPreferredIOBlockSizeKey` as well (imports[403], lib_ordinal 9 = CoreFoundation, already
  exported) and dereferences it at 0x10e02 (`movq <sym>(%rip), %rax; movq (%rax), %rdi`) to build the
  key set it passes to `resourceValues(forKeys:)`; the getter itself is called at 0x10e73 (through the
  chained-fixups stub at 0x5ba28c, `jmpq *0x6fc0b8(%rip)` -- the GOT slot its bind fixup names). The
  result is **read and used**: `movq %rax, %r14` / `movl %edx, %ebx`, then
  `testb $1, %bl; movl $0x100000, %eax; cmoveq %r14, %rax; movq %rax, -0xc0(%rbp)` -- the value is
  kept, and only when it is absent does the caller fall back to a constant 1 MiB (0x100000) I/O block
  size. So a real block size matters: an invented constant would silently size real I/O buffers.
- **Artifact and measured result.** The name (and its `vpMV` value-witness) are in the deployed export
  tries of **both** prefix roots; `libswiftFoundation.dylib` sha256
  `efdc4ddd0bcb5a05e2f9542444bf9f8be856c53102c2e0da7b62fd9808234f6f` (x86_64-only; built = payload =
  staged = both deployed prefix roots = receipt). The trie diff against the previous copy is **+2
  names, 0 removed** (the getter and `preferredIOBlockSizevpMV`). The bootstrap's guest smoke passed
  and the receipt validates.

## ContentDelivery's `String(contentsOfFile:encoding:)`, the key beside it, and NWPathMonitor (the ContentDelivery rung)

Three demands of one image, in the order the loader applies them. Read off the coverage graph over the
guest's own run log (`--entry private/var/tmp/xcodebuild-minproj.out`): Xcode 26.3's
`Contents/SharedFrameworks/ContentDelivery.framework/Versions/A/ContentDelivery` (built for Mac OS X
14.0) has thirteen unmet eager demands, two in the field image
`/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation` and eleven in
`/System/Library/Frameworks/Network.framework/Versions/A/Network`, all strong and all in
`__DATA_CONST,__got` of its `LC_DYLD_CHAINED_FIXUPS` image.

**The order is the fixup table's, not the graph's `--order` list.** The predicted stop sequence sorts
one image's unmet demands by symbol name (`closure_analyze.py:2407`), which puts the eleven Network
names first; the live run stopped on `String(contentsOfFile:encoding:)` instead. The image's own
fixup table is the truth: contentsOfFile is bind ordinal 38 at 0x189130,
`_NSURLErrorBackgroundTaskCancelledReasonKey` is 74 at 0x189250, and the eleven Network names are
251-261 at 0x1897d8-0x189828 -- ascending, which is the order dyld walks a chained-fixups page. The
key therefore sits BETWEEN contentsOfFile and NWPathMonitor, and the Network names are reached only
once it resolves.

- **`String(contentsOfFile:encoding:)`.** Declaration: the guest SDK's `Foundation.swiftinterface`
  line 15519, in `extension Swift.String` (15513): `public init(contentsOfFile path: __shared
  Swift.String, encoding enc: Swift.String.Encoding) throws`. Body verbatim from the release/5.4
  Darwin overlay this file is based on, which is also what the in-tree copy of that file carries
  (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:343`): the read is the tree's own
  `-[NSString initWithContentsOfFile:encoding:error:]` (src/external/foundation/src/NSString.m:826,
  a real read through `_NSReadBytesFromFile`), and the only work here is the bridge. A file that
  cannot be read throws that initializer's `NSError` rather than returning a wrong string.
  **Measured client use (x86_64 slice):** one call site, 0x12c360, through the chained-fixups stub at
  0x1448ae (`jmpq *0x189130(%rip)`), with `String.Encoding.utf8` fetched immediately before it
  (0x12c34f calls the stub for `...EncodingV4utf8ACvgZ`); the returned `String` (`%rax`/`%rdx`) is
  consumed by the function at 0x12b3e0, whose first action is a `CharacterSet` metadata accessor. The
  client builds a character set out of the file it read, so a wrong or truncated string would silently
  change what that set contains.
- **`_NSURLErrorBackgroundTaskCancelledReasonKey`.** An `NSString * const`, not a function: the client
  loads the symbol's slot and dereferences the pointer it holds (0x4088f `movq <got>, %rax`; 0x40896
  `movq (%rax), %rdx`) and hands the object to `-[NSDictionary objectForKeyedSubscript:]` (0x408a0).
  A Swift global of class type is initialized lazily, so a client that reads the storage directly --
  as this one does -- would read NULL; the symbol has to be a real C constant. The tree's own five
  keys of this family live in src/external/foundation/src/NSURLError.m (`NSString *const
  NSURLErrorDomain = @"NSURLErrorDomain";` and four more, declared in
  src/external/foundation/include/Foundation/NSURLError.h), and that tree is off limits to this wave,
  so the constant is defined in the Foundation overlay (overlays/Foundation/NSURLErrorConstants.m,
  compiled by build-arch.sh into libswiftFoundation.dylib, which Foundation.framework re-exports as an
  ordinal -- the route the client binds it by). The value is Apple's own, from open source this tree
  carries: swift-corelibs-foundation/Sources/Foundation/NSURLError.swift:37.
- **Eleven Network names: `NWPathMonitor` and `NWPath.Status`.** Declarations: the guest SDK's
  `Network.swiftinterface` -- the class at 945, `pathUpdateHandler` at 955, `start(queue:)` at 960,
  `cancel()` at 961, `init(requiredInterfaceType:)` at 976; `NWPath.Status` at 877 (cases 878-880) and
  `NWPath.status` at 887. **Measured client use:** the metadata accessor plus
  `init(requiredInterfaceType:)` (0x128d56, 0x128d70), the handler installed through the setter
  (0x128f32), `start(queue:)` on a real dispatch queue (0x128f71), `cancel()` on teardown (0x1290f2,
  0x129177), and the handler (0x129000) READS `path.status` (0x12903d, through `NWPath.Status`'s
  metadata at 0x129016) and maps it to 1/0/2/-1 for satisfied/unsatisfied/requiresConnection/unknown
  (0x12904d-0x1290a8). What is real: the monitor's construction state and the guest's own observation
  -- there is no path, which the tree says itself (libnetwork answers every path query with a stub:
  `nw_path_get_status` returns `nw_path_status_invalid`, `nw_path_monitor_create` returns NULL,
  src/external/libnetwork/src/nw/path.m:141-147,179-215), and `NWPath.Status.unsatisfied` is Apple's case for
  exactly that. So `start(queue:)` delivers the unsatisfied current path once, on the given queue, the
  way Apple's monitor delivers the initial path, and `cancel()` is a no-op: no transport operation is
  performed and no success is claimed, which is why this is not one of the `NWConnection`-style
  refusals. `.requiresConnection` and `.satisfied` would claim an interface exists; neither is ever
  produced. Apple's `@Sendable` on `pathUpdateHandler` is deliberately not reproduced -- the demand's
  own symbol is `...17pathUpdateHandleryAA0B0VcSgvs`, with no `Y` marker, and `@Sendable` would mangle
  one.
- **Artifacts and measured result.** `libswiftFoundation.dylib` sha256
  `2f159795d09bcf064cdb8007de37298d28265d812e9a42fdf2b9e33ddaedaedc` (x86_64-only; built = payload =
  staged = both deployed prefix roots = both receipt rows), trie **+2 names, 0 removed** (the init and
  the key); `libswiftNetwork.dylib` sha256
  `acc0c0374d0c71db619a7eeba377db105f41993d4bcedf2bc28b75965de24de4` (same chain), trie **+33 names, 1
  removed** -- the removed one is the replaced `NWPath.init(localEndpoint:remoteEndpoint:)`, which no
  image in the closure binds. ContentDelivery's own thirteen imports now resolve against the deployed
  tries (weak=False, eager=True, field Foundation and Network), the bootstrap's guest smoke passed and
  the receipt validates. The graph over the run's own log went Foundation-field 51 -> 49 (exactly these
  two) and Network-field 11 -> 0, with zero hits for any of the names in either guest log or either
  harness log. The ladder advanced past all three groups and now stops on the next ContentDelivery
  demand, `_OBJC_CLASS_$_NSURLSessionDownloadTask` (see below).
- **What the next stop is, and why the graph did not predict it.** The live run's new stop is
  `Symbol not found: _OBJC_CLASS_$_NSURLSessionDownloadTask` / `Referenced from
  .../ContentDelivery.framework/Versions/A/ContentDelivery` / `Expected in:
  /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation` -- an ObjC class the macOS 26
  SDK's own `Foundation.tbd` lists under `objc-classes`, i.e. a real Foundation-field demand. The graph
  does not list it as unmet: `_cover_label` labels it `satisfiable-by-load-order` (the only such import
  of the 88,659) because another image the process loads, the prefix's `CFNetwork.framework` (which
  does export `_OBJC_CLASS_$_NSURLSessionDownloadTask`), carries the name. That model step is wrong for
  this import: ContentDelivery is a `TWOLEVEL` image and the import names an ordinal (1 = Foundation),
  so dyld searched Foundation and its re-exports only -- `Foundation` re-exports just
  `CoreFoundation`, `libobjc.A.dylib` and `libswiftFoundation.dylib` -- and the run proves it by
  aborting. The class's route is therefore the tree's Foundation (`src/external/foundation/src/*`,
  off limits to this wave) or a re-export edge from Foundation to CFNetwork; neither is this rung's, so
  it is reported, not chased.

## ContentDelivery's `NSURLSessionDownloadTask` (the URLSession-class rung)

The Foundation-field name the loader stops on next, and the first one that is an Objective-C **class
object** rather than a function.

- **What the rung is.** Xcode 26.3's `Contents/SharedFrameworks/ContentDelivery.framework/Versions/A/ContentDelivery`
  (minOS 14.0, SDK 26.2) binds four NSURLSession classes eagerly and strongly from ordinal 1 =
  Foundation, in `__DATA,__objc_classrefs` of its `LC_DYLD_CHAINED_FIXUPS` image:
  `_OBJC_CLASS_$_NSURLSessionConfiguration` (imports[416]), `_OBJC_CLASS_$_NSURLSession` (417),
  `_OBJC_CLASS_$_NSURLSessionUploadTask` (423) and `_OBJC_CLASS_$_NSURLSessionDownloadTask` (424).
  Three of the four already resolve: the deployed `Foundation.framework` binary's export trie
  re-exports them from CFNetwork, because `src/external/foundation/reexport_x86_64.exp` names them
  (lines 121, 122 and 128) and Foundation links CFNetwork as an input while passing that file to ld64
  as `-reexported_symbols_list`. The fourth is the stop: the deployed `CFNetwork.framework` **does**
  define the class and its trie carries it (export address 0x75910), but in that `.exp` file line 123
  (`#_OBJC_CLASS_$_NSURLSessionDownloadTask`) -- and its metaclass at line 154 -- are **commented
  out**, so Foundation's trie has no entry for it and dyld, searching Foundation and its re-exports
  only, aborts. `src/external/foundation` is another workstream's this wave, so the missing re-export
  is added here instead, in the overlay Foundation already re-exports as an ordinal
  (`src/external/foundation/CMakeLists.txt`: `-reexport_library src/external/swift/libswiftFoundation.dylib`).
- **What ContentDelivery does with each class (measured, x86_64 slice, not assumed).** The two *task*
  classes are never allocated and never messaged. Every one of `NSURLSessionDownloadTask`'s six call
  sites is the same type test -- `movq <classref>,%rdi; callq _objc_opt_class; movq <task>,%rdi;
  movq %rax,%rsi; callq _objc_opt_isKindOfClass` -- inside URLSession delegate callbacks: 0x4cb6c and
  0x4ce4e in `-[CDUploader URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:]`
  and `-…:didCompleteWithError:`, 0x94095 and 0x9436e in the same two of `CDFileUploader`, 0x111f17 and
  0x112689 in the same two of `CDNetworkAction`. `NSURLSessionUploadTask`'s eight sites are the
  identical shape (`-[CDUploader URLSession:dataTask:didReceiveData:]` 0x4c029, `-[CDFileUploader …]`
  0x93569, and their `didSendBodyData:`/`didCompleteWithError:` pairs). So for these two classes the
  only thing demanded is their **identity in a type test**; no operation is called, so none can fail.
  The other two are class methods on the class object: `NSURLSession` gets
  `+sessionWithConfiguration:delegate:delegateQueue:` (0x28bda, 0x28da5, 0x2fd51, 0xb9cce) and
  `NSURLSessionConfiguration` gets `+defaultSessionConfiguration` (0xb9c08),
  `+ephemeralSessionConfiguration` (0x28b60, 0x28d24, 0x2fcdb) and
  `+backgroundSessionConfigurationWithIdentifier:` (0x28cf4). Nothing in the image allocates any of
  the four; the allocation happens inside the tree's own `+sessionWithConfiguration:…`.
- **The class objects themselves are the tree's, and real.** `src/external/cfnetwork/src/URL/NSURLSession.m`
  defines `@implementation NSURLSessionDownloadTask` (line 34, with no methods) against
  `src/external/foundation/include/Foundation/NSURLSession.h:142`, whose interface declares it a
  subclass of `NSURLSessionTask`; the deployed class object's own metadata reads
  `superclass _OBJC_CLASS_$_NSURLSessionTask`, `baseMethods 0`, and the same holds for the whole
  family (`NSURLSession`/`NSURLSessionTask`/`NSURLSessionTaskMetrics`/`NSURLSessionConfiguration` :
  NSObject, `NSURLSessionDataTask` : NSURLSessionTask, `NSURLSessionUploadTask` : NSURLSessionDataTask).
  So the class object is not empty in the sense of being unusable: it is the exact object Apple's
  `-isKindOfClass:` argument is, with the real superclass, and the tree has carried it all along.
- **The route: a re-export, not a class definition and not a shim of failing operations.** Defining
  the class in the overlay was rejected on measurement: the tree already defines it, CFNetwork is
  loaded whenever Foundation is, and a second class object with one name in one process is resolved by
  the Objective-C runtime arbitrarily -- the loader would then be serving a duplicate, not a
  definition. A shim of explicit-failing operations was rejected because nothing is demanded of this
  class: there is no operation to fail, and methods nobody calls would be a second convention for a
  class the tree already ships, contradicting the Swift half of the same family (`URLSession.swift`
  exists because `URLSession.data(for:delegate:)` IS demanded and cannot be served). Instead
  `overlays/Foundation/NSURLSessionDownloadTask.exp` names the single symbol, `build-arch.sh`/`build.sh`
  link CFNetwork as a **plain input** (not `-reexport_library`, which would re-export all of it) and
  pass that file as `-reexported_symbols_list`, so ld64 resolves the symbol as a proxy from CFNetwork
  and promotes that one atom to global (its `Resolver` does this on `shouldReExport(name) &&
  canReExportSymbols()`). The result is the same shape Foundation uses for the six siblings: a trie
  entry `[re-export] _OBJC_CLASS_$_NSURLSessionDownloadTask (from CFNetwork)` pointing at an ordinal.
  The metaclass is deliberately not listed: no image in the closure binds
  `_OBJC_METACLASS_$_NSURLSessionDownloadTask` (checked against all 88,659 imports), and
  `-isKindOfClass:` never needs it. The sibling classes' convenience constructors that the tree does
  not implement (`+ephemeralSessionConfiguration` and `+backgroundSessionConfigurationWithIdentifier:`
  are declared in `NSURLSession.h:150` but implemented nowhere in `src/external/cfnetwork`) are
  recorded, not chased: they are not loader stops, and they belong to the tree's own workstream.
- **Artifact and measured result.** `libswiftFoundation.dylib` sha256
  `d06e55a393d350e3d4e7aac85054513ba07e5ab4033b411b9b61d2672809602c` (x86_64-only; built = payload =
  staged = **both** deployed prefix roots = both receipt rows). The trie diff against the previous
  copy is **+1 name, 0 removed** (8,341 -> 8,342); CFNetwork appears as a new plain `LC_LOAD_DYLIB`
  dependency, which adds no image to the process (Foundation already loads it). The bootstrap's guest
  smoke passed (`WEST_PREFIX_BOOTSTRAP_OK`) and the receipt validates. ContentDelivery's own four class
  imports now all resolve against the deployed tries (ordinal 1, weak=False, eager=True): the three
  siblings through Foundation's own trie, DownloadTask through `libswiftFoundation`'s trie, which
  Foundation re-exports. The ladder advanced past it -- one run, both workloads: **XCB_RC=132** in
  both (the standing abort/SIGILL gap, not this rung's), harness VERDICT FAIL, no artifact -- and both
  guest logs now read `Symbol not found: _$sSy10FoundationE15appendingFormatySSqd___s7CVarArg_pdtSyRd__lF`
  / `Referenced from …/VoiceBoxClient.framework/Versions/A/VoiceBoxClient` (built for Mac OS X 14.0) /
  `Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`, with zero hits
  for `NSURLSessionDownloadTask` in either guest log or either harness log. The graph over that run's
  own log moves exactly one import: `satisfiable-by-load-order` 1 -> 0 and `reexport` 13,838 -> 13,839
  (the model had flagged this one import against a loaded image while the loader searches an ordinal
  -- the discrepancy the ContentDelivery rung reported, now resolved in the model's own counts).

## ContentDeliveryServices' `StringProtocol.appendingFormat(_:_:)` and `NSURLSessionTaskTransactionMetrics` (the VoiceBoxClient rung)

The Foundation-field names the loader stops on next, in an image the ladder reaches through
`ContentDeliveryServices.framework` -> `AppStoreService.framework` -> `VoiceBoxClient.framework`.

- **What the rung is.** `VoiceBoxClient` (Xcode 26.3, `Contents/SharedFrameworks/ContentDeliveryServices.framework/Versions/A/Frameworks/VoiceBoxClient.framework/Versions/A/VoiceBoxClient`,
  built for Mac OS X 14.0) has 551 chained-fixup imports over 13 dependencies. Resolved against the
  deployed prefix (the tree's own reader, `closure_analyze.py --cover`): 414 own-export-trie, 131
  reexport, 4 absent-weak, 2 missing. The two `missing` rows are its whole unmet set, both **Foundation**
  field (`lib_ordinal = 2`), both `weak_import = 0`, both eager -- and both were absent from every
  deployed image Foundation's ordinal reaches:
  - `_$sSy10FoundationE15appendingFormatySSqd___s7CVarArg_pdtSyRd__lF` -- chained import[102],
    bound at `__DATA_CONST,__got` 0x4E3C0 (segment 1, page 0);
  - `_OBJC_CLASS_$_NSURLSessionTaskTransactionMetrics` -- chained import[537], bound at
    `__DATA,__objc_classrefs` 0x546B8 (segment 2, page 2).
  The image's own fixup table is the order: dyld walks `__DATA_CONST` (segment 1) before `__DATA`
  (segment 2), so `appendingFormat` is bound first and was the run's stop; `NSURLSessionTaskTransactionMetrics`
  is the stop behind it, which is why this rung answers both. The four other rows are weak edges, not
  stops: `_$s9CryptoKit6SHA384VACycfC`, `_$s9CryptoKit6SHA384VMn`, `_$s9CryptoKit6SHA512VACycfC`,
  `_$s9CryptoKit6SHA512VMn` (CryptoKit, ordinal 1) each bind to NULL.
- **What VoiceBoxClient does with each name (measured on the x86_64 slice, from the image's own
  chained fixups and disassembly -- not assumed).**
  - `appendingFormat` -- ONE call site, 0x1F41B, through the stub at 0x3FC30 (`jmpq *0x4E3C0(%rip)`).
    The format argument is the Swift small-string literal `"%02hhx"` (built inline at 0x1F38D:
    `movabsq $0x786868323025` = `%02hhx` plus the small-string discriminator), one `CVarArg` is boxed
    (`swift_allocObject` at 0x1F3C9, 0x48 bytes), and the returned `String` (`%rax`/`%rdx`) is captured
    at 0x1F420 (`movq %rax,%r14; movq %rdx,%r15`) and returned by the enclosing function at 0x1F469
    (`movq %r14,%rax; movq %r15,%rdx; ... retq`). The result is READ AND USED; there is no second
    call site in the image.
  - `NSURLSessionTaskTransactionMetrics` -- ONE reference to the class: the classref at 0x1E023 inside
    the lazy type-metadata accessor at 0x1E010 (`movq <0x546B8>,%rdi; callq _objc_opt_self; callq
    _swift_getObjCClassMetadata`, whose result is cached). That accessor is called once, at 0x1DC22,
    and its metadata is handed straight to `Array<NSURLSessionTaskTransactionMetrics>._unconditionallyBridgeFromObjectiveC`
    (stub 0x3FB8E -> GOT 0x4E3A8) applied to the NSArray returned by `-[NSURLSessionTaskMetrics transactionMetrics]`
    (selector from the selref at 0x54230; `objc_msgSend` at 0x1DC10). The class is never allocated and
    never messaged, and no image in the closure binds its metaclass (checked over all 88,659 imports).
    So the demand is the class OBJECT as the element type of an array bridge -- no operation at all.
- **Per symbol: route and reason.**
  - `StringProtocol.appendingFormat(_:_:)` -- route: the Foundation overlay. Declaration: the guest
    SDK's `Foundation.swiftinterface:22727`, inside `extension Swift.StringProtocol` (22675):
    `public func appendingFormat<T>(_ format: T, _ arguments: any Swift.CVarArg...) -> Swift.String where
    T : Swift.StringProtocol` (mangling `Sy10FoundationE15appendingFormatySSqd___s7CVarArg_pdtSyRd__lF`,
    confirmed with `swift-demangle`). Body verbatim from the release/5.4 Darwin overlay this file is
    based on, which is also what the in-tree copy carries
    (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:1144-1152`): format with
    `String(format:arguments:)` and append over `-[NSString stringByAppendingString:]`
    (src/external/foundation/src/NSString.m:1256, a real concatenation). The in-tree
    `format._ephemeralString` is the `StringProtocol` -> `String` helper, spelled `String(format)`
    here; `_ns` is the file's own receiver bridge. Added to `overlays/Foundation/NSStringAPI.swift`
    (the same file and the same precedent as the two neighbouring rungs).
  - `NSURLSessionTaskTransactionMetrics` -- route: a real Objective-C class in the Foundation overlay
    (`overlays/Foundation/NSURLSessionTaskTransactionMetrics.m`, compiled by `build-arch.sh`/`build.sh`
    and linked into `libswiftFoundation`). Reason: the class is defined nowhere in this tree.
    `src/external/cfnetwork/src/URL/CFNSURLConnection.m:3` defines only the sibling
    `NSURLSessionTaskMetrics`; `src/external/foundation/reexport_x86_64.exp` (line 127 and its
    metaclass at 169) has the class commented out precisely because nothing defines it; the guest SDK
    declares it (`Foundation.framework/Headers/NSURLSession.h:1283`, `@interface
    NSURLSessionTaskTransactionMetrics : NSObject`). Both proper homes are off limits to this wave, so
    a RE-EXPORT (the previous rung's route) is impossible -- there is nothing to re-export -- and the
    class object is DEFINED here instead. The declaration is Apple's; the body is empty on purpose:
    nothing in the closure constructs the class and the tree's `-[NSURLSessionTaskMetrics
    transactionMetrics]` is the forwarding stub in `CFNSURLConnection.m`, so the client's bridged
    array is empty. A property returning an invented snapshot would be a plausible wrong value; an
    empty class object states the truth and any operation on a real instance fails observably
    (unrecognized selector). Foundation.framework re-exports `/usr/lib/swift/libswiftFoundation.dylib`
    as an ordinal (the deployed binary's `LC_REEXPORT_DYLIB`), so the class IS reachable under the
    ordinal the client binds.
- **Artifact and measured result.** `libswiftFoundation.dylib` sha256
  `9a73d5b4f7da58556e16559f9a588c54c5734a387a275d643eeb1e332237f33c` (x86_64-only; built = payload =
  staged = **both** deployed prefix roots = both receipt rows). The trie diff against the previous
  copy is **+3 names, 0 removed** (8,342 -> 8,345): `_$sSy10FoundationE15appendingFormatySSqd___s7CVarArg_pdtSyRd__lF`,
  `_OBJC_CLASS_$_NSURLSessionTaskTransactionMetrics` and `_OBJC_METACLASS_$_NSURLSessionTaskTransactionMetrics`
  (the metaclass comes with the class object; nothing imports it). The previous artifact was
  `d06e55a393d350e3d4e7aac85054513ba07e5ab4033b411b9b61d2672809602c`. The bootstrap's guest smoke
  passed (`WEST_PREFIX_BOOTSTRAP_OK`) and the receipt validates. VoiceBoxClient's own two binds now
  resolve against the deployed tries (ordinal 2, weak=False, eager=True) through `libswiftFoundation`'s
  trie, which Foundation re-exports. The ladder advanced past the image -- one run, both workloads:
  **XCB_RC=132** in both (the standing abort/SIGILL gap, not this rung's), harness VERDICT FAIL, no
  artifact -- and both guest logs now read `Symbol not found: _CGImageSourceCopyProperties` /
  `Referenced from …/AppStoreService.framework/Versions/A/AppStoreService` (built for Mac OS X 14.0) /
  `Expected in: /System/Library/Frameworks/ImageIO.framework/Versions/A/ImageIO`, with zero hits for
  `appendingFormat`, `NSURLSessionTaskTransactionMetrics` and every previous rung's name in either
  guest log or either harness log. The graph over that run's own log moves exactly the two imports:
  `missing` 78 -> 76 and `reexport` 13,839 -> 13,841. The import universe also grows by 5 (88,659 ->
  88,664), all five inside this overlay: the new class object makes `libswiftFoundation` itself
  reference `_OBJC_CLASS_$_NSObject`, `_OBJC_METACLASS_$_NSObject` (twice) and `__objc_empty_cache`
  (twice) from the runtime, and all five resolve.

## DVTAppStoreConnect's `URL.init?(string:encodingInvalidCharacters:)` (the URL-string-init rung)

- **What the rung is.** `DVTAppStoreConnect` (Xcode 26.3,
  `Contents/SharedFrameworks/DVTAppStoreConnect.framework/Versions/A/DVTAppStoreConnect`, reached
  through `IDEDistribution`'s loader closure) demands ONE name of the Foundation field and nothing
  else: of its 1,234 eager, non-weak binds, 1,233 resolve against the deployed components and this
  one does not. The stop moved here after the ImageIO rung:

  ```
  Symbol not found: _$s10Foundation3URLV6string25encodingInvalidCharactersACSgSSh_SbtcfC
    Referenced from: .../SharedFrameworks/DVTAppStoreConnect.framework/Versions/A/DVTAppStoreConnect
    Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
  ```

- **The whole image, not the model's first name.** `DVTAppStoreConnect` is a chained-fixups image;
  decoding it (segments in load-command order, pages ascending, chain position inside the page)
  gives 1,234 binds and puts this name at rank 716, in `__DATA_CONST,__got` at vmoff `0x85808`. It
  is the only unmet bind in the image, so it is both the first and the last stop the image can make.
  The stop model sorts one image's names by symbol name; dyld walks segments and pages first, which
  is why the 654 `XCServices`, 17 `DVTFoundation` and 25 `Combine` binds are all already resolved by
  the time it is reached.

- **Per symbol: route and reason.**
  - `URL.init?(string:encodingInvalidCharacters:)` — `_$s10Foundation3URLV6string25encodingInvalidCharactersACSgSSh_SbtcfC`.
    Route: the Foundation overlay (`overlays/Foundation/URL.swift`), linked into
    `libswiftFoundation`; `Foundation.framework` re-exports `/usr/lib/swift/libswiftFoundation.dylib`
    as an ordinal, which is the ordinal the client binds (lib ordinal 5 = Foundation), so the name is
    reachable under the image the loader names. Declaration: the guest SDK's
    `Foundation.swiftinterface` lines 16316-16317 (x86_64 slice),
    `@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)`,
    `public init?(string: __shared Swift.String, encodingInvalidCharacters: Swift.Bool)`; the SDK's
    `NSURL.h:70-77` carries the same contract and the Objective-C twin. Body: Apple's own, from the
    swift-foundation committed under `overlays/build/swift-foundation`
    (`Sources/FoundationEssentials/URL/URL.swift:705-711`, commit `dbacc677`), over surfaces this
    tree already has. Apple delegates to `NSURL.init(string:encodingInvalidCharacters:)`, and this
    tree has no `encodingInvalidCharacters` anywhere in `src/external/foundation` or
    `src/external/corefoundation`, so the two branches use the two surfaces that do exist: the
    strict branch (`false`) is this tree's `URLComponents(string:)`, whose `_isValidPercentEncoded`
    is exactly Apple's "invalid according to RFC 3986 -> `nil`, characters left as they are"; the
    encoding branch (`true`) is `NSURL(string:)`, the surface this file's own `init?(string:)` uses,
    because the tree has no encoder to point at. **The `true`/`false` semantics matter and are
    documented backwards in places**: `true` attempts the encoding, `false` returns `nil` for an
    RFC 3986-invalid string (SDK `NSURL.h:70`, swift-foundation `URL.swift:705`). The client passes
    `false`, measured at both of its call sites (`xorl %edx,%edx` before each call), and checks the
    `nil` — so the wrong branch on `nil` would hand it a URL it never asked for. Returning `nil` for
    an encodable string in the `true` branch is the honest failure this tree can state; no client in
    this closure passes `true`.

- **Artifact and measured result.** `libswiftFoundation.dylib` sha256
  `82f1befcc0eee49a12508f68875ebb101aaa0eb93cea747774f453adcee61701` (x86_64-only; built = payload =
  staged = **both** deployed prefix roots = both receipt rows). The trie diff against the previous
  copy is **+1 name, 0 removed** (8,345 -> 8,346). The bootstrap's guest smoke passed
  (`WEST_PREFIX_BOOTSTRAP_OK`), the receipt validates and the runtime doctor passes.
  `DVTAppStoreConnect`'s whole bind table re-decoded and re-resolved against the deployed tries now
  reports **zero unmet** binds (the image's own graph labels: 989 own-export-trie, 52 reexport, no
  absent/missing class). The ladder advanced past the image — one run, both workloads: **XCB_RC=132**
  in both (the standing abort/SIGILL gap, not this rung's), harness VERDICT FAIL, no artifact — and
  both guest logs now read `Symbol not found:
  _$s7Combine4JustV14setFailureType2tos6ResultOAAE9PublisherVyxqd___Gqd__m_ts5ErrorRd__lF` /
  `Referenced from …/SharedFrameworks/XCSourceControl.framework/Versions/A/XCSourceControl` /
  `Expected in: /System/Library/Frameworks/Combine.framework/Versions/A/Combine`, with zero hits for
  `encodingInvalidCharacters` in either guest log or either harness log. The graph over that run's
  own log moves exactly two imports out of `missing` (76 -> 74): this rung's, and the ImageIO rung's
  C name from the same wave.

## XCSourceControl's `Just.setFailureType(to:)` and `Result.Publisher` (the Combine-result-publisher rung)

- **What the rung is.** `XCSourceControl` (Xcode 26.3,
  `Contents/SharedFrameworks/XCSourceControl.framework/Versions/A/XCSourceControl`, reached through
  `IDEFoundation`'s loader closure) demands FOUR names of the **Combine** field, and every other
  component it binds resolves. The stop moved here after the URL-string-init rung:

  ```
  Symbol not found: _$s7Combine4JustV14setFailureType2tos6ResultOAAE9PublisherVyxqd___Gqd__m_ts5ErrorRd__lF
    Referenced from: .../SharedFrameworks/XCSourceControl.framework/Versions/A/XCSourceControl
    Expected in: /System/Library/Frameworks/Combine.framework/Versions/A/Combine
  ```

- **The whole image, not the model's first name.** `XCSourceControl` is a chained-fixups image;
  decoding it (segments in load-command order, pages ascending, chain position inside the page)
  gives **1246 binds**, of which the four Combine demands are at walk #18, #26, #27 and #28, all in
  `__DATA_CONST,__got`, all strong and eager, all against ordinal 2 =
  `/System/Library/Frameworks/Combine.framework/Versions/A/Combine`. The first unmet bind in that
  order is #18, the function; the model's name-sorted list reaches the same four names in a different
  order (#3, #8, #9, #10), because dyld walks segments and pages, not symbol names.

- **Per symbol: route and reason.** All four are the same nesting mistake, so one source change
  answers all four: patch `0004-nest-result-publisher-directly.patch` moves OpenCombine's
  `Result.OCombine.Publisher` struct (and its private `Inner` subscription) out of the `OCombine`
  namespace to be a real nested type `Result.Publisher`, and repoints every
  `Result<...>.OCombine.Publisher` in the module at it. Darling builds OpenCombine as the module
  `Combine`, so the namespace cannot disambiguate anything here.
  - `_$s7Combine4JustV14setFailureType...` (`Combine.Just.setFailureType<E>(to:) -> Result<Output, E>.Publisher`)
    — route: the declaration's return type follows the moved struct, so the mangled name now carries
    Apple's `9PublisherV` instead of `8OCombineV9PublisherV`. Body: OpenCombine's own
    `return .init(output)` — a `Just` cannot fail, so the returned publisher carries the output as a
    `.success` and the new failure type stays a type parameter. That is Apple's contract for
    `setFailureType(to:)`, so the implementation is unchanged.
  - `_$ss6ResultO7CombineE9PublisherVMa` (type metadata accessor) — route: emitted by the compiler
    for the new real struct; the client calls it to materialize `Result<Output, Error>.Publisher`
    metadata for its own instantiation.
  - `_$ss6ResultO7CombineE9PublisherVMn` (nominal type descriptor) — route: emitted with the struct;
    the client's own local metadata records (`..._GMd`/`..._GMR`) for
    `Result<XCSourceControl.XCSourceControlHostBranch, Error>.Publisher` need it.
  - `_$ss6ResultO7CombineE9PublisherVyxq__GAcdCMc` (conformance descriptor for
    `Result<A, B>.Publisher : Combine.Publisher`) — route: emitted for the struct's conformance to
    `Combine.Publisher`; the client passes it to `_swift_getWitnessTable` to dispatch a `Publisher`
    protocol extension method on the returned value.
  A typealias could not have supplied any of the three type symbols (it gets no nominal type
  descriptor of its own), which is why this is source work and not an un-guarding of OpenCombine's
  `#if !canImport(Combine)` block.

- **Declarations, from the guest SDK.** `Combine.framework/Versions/A/Modules/Combine.swiftmodule/
  x86_64-apple-macos.swiftinterface` in the Xcode 26.3 MacOSX SDK: line 592
  `public func setFailureType<E>(to failureType: E.Type) -> Swift.Result<Output, E>.Publisher
  where E : Swift.Error`; lines 1727-1739 `extension Swift.Result { public var publisher: ...;
  public struct Publisher : Combine.Publisher { public typealias Output = Success; public let result:
  Result<...>; public init(_ ...); public func receive<S>(subscriber: S) ... } }`; line 1845-1848 the
  `Result.Publisher where Failure == Never` sibling of `setFailureType`. The muddled model, not the
  source: the module's own `OCombine.Publisher` already implemented exactly this publisher
  (`receive(subscriber:)` sends the value and `.finished` through `Inner` on `.success`, and
  `Subscriptions.empty` plus the failure on `.failure`), so the move is mechanical.

- **The client's measured use** (five call sites: `0x24644`, `0x5669d`, `0x57650`, `0x57bd7`,
  `0x5804d`). At each one the client calls `_$ss6ResultO7CombineE9PublisherVMa`, builds the `Just`,
  calls `setFailureType(to: Error.self)`, loads
  `_$ss6ResultO7CombineE9PublisherVyxq__GAcdCMc` into `%rdi` with the metadata in `%rsi`, calls
  `_swift_getWitnessTable`, and then calls `Publisher.eraseToAnyPublisher()` on the result. So the
  returned value really is used as a `Publisher` through its conformance, and the honest behaviour
  the module must supply is the one OpenCombine already had; a wrong-typed or absent conformance
  would fail at the `swift_getWitnessTable` dispatch rather than at the load.

- **Artifact and measured result.** `Combine.framework/Versions/A/Combine` sha256
  `a7ae9b1642916cee7e2d34b5920473d27c8f9d2a9387f513674f0b3322b69047` (x86_64-only; the file every
  earlier wave left modified is from this rung on this rung's own artifact, built = payload = staged
  = **both** deployed prefix roots = both receipt rows). Built with the new focused path
  `DARLING_SWIFT_COMBINE_ONLY=1 sh overlays/build-arch.sh` (offline: `OPENCOMBINE_SRC` points at the
  existing pinned `10df981` checkout), deployed with `cmake --regenerate-during-build` plus
  `west darling-bootstrap` (real build). The deployed export trie is **1680 names before and after**;
  the diff is 63 removed / 63 added, every removal a `8OCombineV9PublisherV` spelling (61) or the
  `OCombine.publisher` getter whose return type changed (2), every addition the corresponding Apple
  spelling plus the four symbols of the type itself. **None of the 63 retired names is imported by
  any of the 254 images in the ladder's load closure** (measured over the closure's own 88600
  imports). `XCSourceControl`'s whole bind table re-decoded and re-resolved against the deployed
  tries: Combine field 25 binds, **0 unmet**, 0 unmet non-weak; first unmet in its walk order is now
  #174, `_$sSo12NSURLSessionC10FoundationE17DataTaskPublisherV7Combine0E0ACMc`, a **Foundation**
  name. One ladder run, both workloads: **XCB_RC=132** in both (the standing abort/SIGILL gap),
  harness VERDICT FAIL, no artifact, and both guest logs now read `Symbol not found:
  _$sSo12NSURLSessionC10FoundationE17DataTaskPublisherV7Combine0E0ACMc` / `Referenced from
  …/SharedFrameworks/XCSourceControl.framework/Versions/A/XCSourceControl` / `Expected in:
  /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`, with zero hits for
  `setFailureType2to` or `ResultO7CombineE9Publisher` in either guest log or either harness log. The
  graph over the closure moves exactly four imports out of `missing` (74 -> 70) and no longer lists
  a single unmet demand whose field is Combine: the module's part of this image's demand is closed,
  and the stop is Foundation's (`NSURLSession.DataTaskPublisher`, `String.lengthOfBytes(using:)`).

## XCSourceControl's `URLSession.dataTaskPublisher(for:)`, its `DataTaskPublisher` and `StringProtocol.lengthOfBytes(using:)` (the DataTaskPublisher rung)

- **What the rung is.** `XCSourceControl` (Xcode 26.3,
  `Contents/SharedFrameworks/XCSourceControl.framework/Versions/A/XCSourceControl`, reached through
  `IDEFoundation`'s loader closure) demands FOUR names of the **Foundation** field, and every other
  component it binds resolves. The stop moved here after the Combine-result-publisher rung:

  ```
  Symbol not found: _$sSo12NSURLSessionC10FoundationE17DataTaskPublisherV7Combine0E0ACMc
    Referenced from: .../SharedFrameworks/XCSourceControl.framework/Versions/A/XCSourceControl
    Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
  ```

- **The whole image, not the model's first name.** `XCSourceControl` is a chained-fixups image;
  decoding it (segments in load-command order, pages ascending, chain position inside the page) gives
  **1246 binds**, of which exactly four are unmet, all Foundation-field (ordinal 4), all strong and
  eager, all in `__DATA_CONST,__got`: walk **#174** `_…DataTaskPublisherV7Combine0E0ACMc`,
  **#175** `_…DataTaskPublisherVMa`, **#176** `_…dataTaskPublisher3for…`, **#183**
  `_…lengthOfBytes5using…`. The first unmet bind in that order is #174, the conformance descriptor.
  Every other one of its 1246 binds already resolved (Combine 25, swiftCore 628, libobjc 306,
  CoreFoundation 46, libSystem 21, libswiftDispatch 18, libswiftObjectiveC 5, libswiftos 5,
  CoreServices 4, DVTFoundation 2).

- **Where the declarations come from.** Apple declares `DataTaskPublisher` in the **Foundation**
  overlay, not in Combine: `Foundation.framework/Modules/Foundation.swiftmodule/
  x86_64-apple-macos.swiftinterface` lines 17838-17849 (`@available(macOS 10.15, iOS 13.0, tvOS 13.0,
  watchOS 6.0, *) extension Foundation.URLSession`) declare both `dataTaskPublisher(for:)` overloads
  and `public struct DataTaskPublisher : Combine.Publisher, Swift.Sendable` with
  `Output = (data: Data, response: URLResponse)`, `Failure = URLError`, `init(request:session:)` and
  `receive(subscriber:)`; `Combine.swiftinterface` carries no `DataTaskPublisher` (measured: 0 hits).
  The mangling's `10FoundationE` matches that placement. `lengthOfBytes(using:)` is
  `Foundation.swiftinterface:22706` in an `extension Swift.StringProtocol` block.

- **Per symbol: route and reason.**
  - `_…DataTaskPublisherV7Combine0E0ACMc` (conformance descriptor for
    `NSURLSession.DataTaskPublisher : Combine.Publisher`) — route: declare the struct in
    `Foundation/URLSession.swift` conforming to `Combine.Publisher`; the descriptor is emitted with
    the conformance. The client passes it to `_swift_getWitnessTable` from its own `Wl` accessor, so
    the witness table must be real.
  - `_…DataTaskPublisherVMa` / `_…VMn` (metadata accessor and nominal descriptor) — route: emitted by
    the compiler for the public struct (the overlay is built `-enable-library-evolution`); the client
    calls `VMa` directly at `0x240ea` and inside `Wl` at `0x264a6`. A `typealias` could not supply
    them.
  - `_…dataTaskPublisher3forAbCE04DatadE0VAC10URLRequestV_tF` (and the `URL` overload beside it) —
    route: declare it returning the struct, over a body that CANNOT start a task, because this tree
    has no URLSession implementation: the deployed Foundation only *re-exports* the
    `_OBJC_CLASS_$_NSURLSession` **class object** from CFNetwork (the URLSession-class rung) and no
    open source carries an implementation to borrow (OpenCombine's `OpenCombineFoundation`
    `DataTaskPublisher.Inner.request` at `overlays/build/OpenCombine/Sources/OpenCombineFoundation/
    URLSession.swift:169-181` is built on the same `session.dataTask(with:completionHandler:)`).
    **Explicit failure, not invention**: `receive(subscriber:)` hands `Combine.Fail<Output, URLError>`
    the family's one documented error and lets it perform the standard subscription handshake
    (`Subscriptions.empty`, then the failure on the first demand). The error is built from the single
    helper `_darlingURLSessionUnsupported` that `data(for:delegate:)` throws — `NSFeatureUnsupportedError`
    (3328) in the Cocoa error domain — carried as the `URLError`'s underlying error
    (`NSUnderlyingErrorKey`) with the same localized description, its own code being
    `URLError.Code.unsupportedURL`: `URLError`'s `_nsError` must be in `NSURLErrorDomain`
    (`Foundation/URLError.swift:20-23` preconditions it), so the family's one condition is reported
    through each API's own failure type rather than by inventing a success. Published behaviour:
    `.failure`, never `.finished`.
  - `_$sSy10FoundationE13lengthOfBytes5usingSiSSAAE8EncodingV_tF` — route: add
    `StringProtocol.lengthOfBytes(using:)` to `Foundation/NSStringAPI.swift`, body verbatim from the
    release/5.4 Darwin overlay (and the in-tree copy at
    `swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:999-1001`):
    `Int(_ns.lengthOfBytes(usingEncoding: encoding.rawValue))`. Real: over Darling's own
    `-[NSString lengthOfBytesUsingEncoding:]` (`src/external/foundation/src/NSString.m:1683`,
    an exact `__CFStringEncodeByteStream` count, 0 on conversion error — Apple's documented O(n)
    exact result), with `_ns` this file's own receiver bridge; the selector keeps its ObjC spelling
    because this tree's SDK carries no apinote for it, exactly as the file header notes for
    `data(usingEncoding:)`. The `Sendable` conformance Apple also declares is NOT declared: neither
    `URLRequest` (this tree's overlay) nor the imported `NSURLSession` class is `Sendable` here, so
    asserting it would be a claim the tree cannot make, and no image binds that conformance.

- **What the client does (measured).** All three `DataTaskPublisher` names are used by one function,
  `-[XCSourceControlHostRequestPublisherContext publisher]`: it materializes the metadata
  (`VMa` at `0x240ea`), asks for the `Publisher` witness table through its own `Wl`
  (`0x24154`, `0x26490-0x264c2`), and calls `dataTaskPublisher(for:)` on the `NSURLSession` it stores
  (`0x242d1`), piping the result through `Publishers.TryMap`/`FlatMap`/`eraseToAnyPublisher`. Its
  callers subscribe with `.sink(receiveCompletion:receiveValue:)` (`0x247e0`, `0x249a7`, `0x4a1a3`,
  `0x4a361`) and the completion closure (`0x24820`) reads the `Subscribers.Completion`, so a delivered
  failure is observable. `lengthOfBytes(using:)` is called at `0x6446c`, `0x64f68`, `0x65979`
  (all `.utf8`) and the returned `Int` is read.

- **Artifact and measured result.** `libswiftFoundation.dylib` sha256
  `2913a64c33e41c2042f66387e00ec3bf75022d917da0b7b96ff819dfa8424972` (x86_64-only; built = payload =
  staged = **both** deployed prefix roots = both receipt rows). Built with
  `DARLING_SWIFT_FOUNDATION_ONLY=1 sh overlays/build-arch.sh` (offline; the focused path exits before
  build-arch.sh's bottom copy-into-payload loop, so the built dylib is copied into the payload
  afterwards, as the URL-string-init rung does), deployed with `cmake --regenerate-during-build` plus
  `west darling-bootstrap` (real build). The focused run also rebuilds `Combine.framework/Versions/A/
  Combine` (its build precedes Foundation's in build-arch.sh); that rewrite is byte-identical
  (`a7ae9b16…` before and after), so nothing about the Combine rung's artifact changed and it is not
  restored. The deployed export trie goes **8346 -> 8359 names**, **0 removed / 13 added**: the
  conformance descriptor (`…ACMc`), `receive(subscriber:)`, `init(request:session:)`, the two stored
  properties' getters and property descriptors, the metadata accessor (`Ma`), the nominal descriptor
  (`Mn`), the type metadata (`VN`), the two `dataTaskPublisher(for:)` overloads, and
  `StringProtocol.lengthOfBytes(using:)`. `XCSourceControl`'s
  whole bind table re-decoded against the deployed tries: **0 unmet**, 0 unmet non-weak. Over the
  254-image closure this moves exactly four imports out of `missing` (**70 -> 66**), adds none, and
  the only image whose import list changes is `libswiftFoundation.dylib` itself (88,600 imports
  before the rung / 88,603 after; the three new ones are `+3` eager/strong Combine imports --
  `_$s7Combine4FailV…`, `_$s7Combine4FailVMn`, `_$s7Combine4FailV7receive…` -- all resolving against
  the deployed Combine, none removed). One
  ladder run, both workloads: **XCB_RC=132** in both (the standing abort/SIGILL gap), harness
  VERDICT FAIL, no artifact; the XCSourceControl stop line is gone (0 hits for `DataTaskPublisher`,
  `dataTaskPublisher`, `lengthOfBytes` in either guest log or either harness log) and the loader now
  stops at `_$sSS10FoundationE10contentsOfSSAA3URLVh_tKcfC` (`String.init(contentsOf: URL)`),
  referenced from `…/SharedFrameworks/DVTSmartSearch.framework/Versions/A/DVTSmartSearch` -- the next
  rung.

## DVTSmartSearch's `String.init(contentsOf: URL)` and `StringProtocol.folding(options:locale:)` (the contentsOf-URL rung)

- **What the rung is.** `DVTSmartSearch` (Xcode 26.3,
  `Contents/SharedFrameworks/DVTSmartSearch.framework/Versions/A/DVTSmartSearch`, reached through
  `DNTDocumentationModel`'s loader closure) is the demanding image of the DataTaskPublisher rung's
  run. It is a chained-fixups image with **555 binds**, every one against a named component, and
  exactly **two** of them unmet -- both in the **Foundation** field (ordinal 4), both strong and
  eager. Every other component it binds resolves 100%: swiftCore 371, swift_Concurrency 34, libobjc
  31, libSystem 17, libswiftDispatch 13, Accelerate 12, libswift_StringProcessing 7, swiftos 6,
  CoreML 6, NaturalLanguage 5, libswiftAccelerate 4, libswiftNaturalLanguage 4, CoreFoundation 1.

- **The image's own bind order.** Decoding `LC_DYLD_CHAINED_FIXUPS` (segments in load-command order,
  pages ascending inside a segment, chain position inside the page -- NOT the model's symbol-name
  sort and NOT the imports table's order) puts the 44 Foundation binds at walk **#14..#54** in
  `__DATA_CONST` page 0. The two unmet names are walk **#38**
  `_$sSS10FoundationE10contentsOfSSAA3URLVh_tKcfC` and walk **#54**
  `_$sSy10FoundationE7folding7options6localeSSSo22NSStringCompareOptionsV_AA6LocaleVSgtF`; the first
  is the loader's stop line and the second the immediate next. The image binds ONE `contentsOf`
  variant (the URL, no-encoding one); the graph's other two `contentsOf` names in the Foundation
  field (`contentsOf:encoding:` and `contentsOf:usedEncoding:`) belong to other images
  (`IDEFoundation`, `CoreDocumentation`, `DNTDocumentationSupport`), not to this image.

- **Per symbol: route and reason.**
  - `_$sSS10FoundationE10contentsOfSSAA3URLVh_tKcfC` (`String.init(contentsOf: URL) throws`) --
    route: add the no-encoding URL initializer to `Foundation/NSStringAPI.swift`. Declaration: the
    guest SDK's `Foundation.swiftinterface` line 22589, in its `extension Swift.String` block
    (`public init(contentsOf url: __shared Foundation.URL) throws`, deprecated there in favour of
    `contentsOf:encoding:`). Body verbatim from the release/5.4 Darwin overlay this file is based on
    (the `contentsOf:` overload that passes `usedEncoding: nil`) and the in-tree copy
    (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:408-414`):
    `try NSString(contentsOf: url, usedEncoding: nil)`. Real: over Darling's own
    `-[NSString initWithContentsOfURL:usedEncoding:error:]`
    (`src/external/foundation/src/NSString.m:990`, a real read of the URL's bytes with BOM/ICU
    encoding detection through `_initWithBytesOfUnknownEncoding:length:copy:usedEncoding:`), and the
    only work here is the bridge. The detected encoding is not reported, exactly as upstream. A URL
    that cannot be read **throws** the `NSError` that initializer produced rather than returning a
    wrong string.
  - `_$sSy10FoundationE7folding7options6localeSSSo22NSStringCompareOptionsV_AA6LocaleVSgtF`
    (`StringProtocol.folding(options:locale:)`) -- route: add it to
    `Foundation/NSStringAPI.swift`. Declaration: the guest SDK's `Foundation.swiftinterface` line
    22734, in its `extension Swift.StringProtocol` block (`public func folding(options:
    Swift.String.CompareOptions = [], locale: Foundation.Locale?) -> Swift.String`). Body verbatim
    from the release/5.4 Darwin overlay (`stdlib/public/Darwin/Foundation/NSStringAPI.swift:1055-1059`)
    and the in-tree copy (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:1165-1169`):
    `_ns.folding(options: options, locale: locale)`. Real: over Darling's own
    `-[NSString stringByFoldingWithOptions:locale:]`
    (`src/external/foundation/src/NSString.m:1766`), which is a real `CFStringFold` (case, diacritic
    and width folding over ICU), not a pass-through. The ObjC selector imports as
    `folding(options:locale:)` -- the Swift 3 rename the importer carries for
    `stringByFoldingWithOptions:locale:` (measured: the old spelling is `obsoleted: 3` and renamed).
    `String.CompareOptions` is this file's own typealias for `NSStringCompareOptions`, so the
    mangling keeps `So22NSStringCompareOptionsV`.

- **What the client does (measured).** `String.init(contentsOf: URL)` has one call site, `0x2aa5c` in
  `…DVTBERTVocabularyV10contentsOfACSg10Foundation3URLV_tcfC` (`DVTBERTVocabulary.init?(contentsOf:)`):
  the next instructions test the thrown error (`testq %r12,%r12`; `je` to the parse path), and on
  the throw path release it (`_swift_errorRelease`), zero the result struct and return **nil** -- the
  failable initializer yields nil on a read failure, so an honest throw is observable and a
  fabricated string would be parsed as a BERT vocabulary (the success path splits it with
  `components(separatedBy: .newlines)`). `folding(options:locale:)` has FOUR call sites, all passing
  `options = 0x80` (`.diacriticInsensitive`) and a `Locale`: `0x16784`
  (`DVTBERTTokenizerWrapper.encode(text:)`), `0x16d79` (`…encodeToIds(text:)`), `0x2af73`
  (`DVTBERTTokenizer.tokenize(string:)`) and `0x2b3f5` (`DVTBERTTokenizer.foldAndTransform(_:)`, a
  tail call whose result IS the return value); every returned `String` is kept and passed on, so the
  fold must actually strip diacritics.

- **Artifact and measured result.** `libswiftFoundation.dylib` sha256
  `0652bb60af6ecb55727837141762896d92c32ee60ab19d4b701f5181d83d0273` (x86_64-only; built = payload =
  staged = **both** deployed prefix roots = both receipt rows). Built with
  `DARLING_SWIFT_FOUNDATION_ONLY=1 sh overlays/build-arch.sh` (offline; the focused path exits before
  build-arch.sh's bottom copy-into-payload loop, so the built dylib is copied into the payload
  afterwards), deployed with `cmake --regenerate-during-build` plus `west darling-bootstrap` (real
  build). The focused run also rebuilds `Combine.framework/Versions/A/Combine`; that rewrite is
  byte-identical (`a7ae9b16…` before and after), so nothing about the Combine rung's artifact changed
  and it is not restored. The deployed export trie goes **8359 -> 8361 names**, **0 removed / 2
  added** -- exactly `String.init(contentsOf: URL)` and `StringProtocol.folding(options:locale:)`.
  `DVTSmartSearch`'s whole bind table re-decoded against the deployed tries: **0 unmet**, 0 unmet
  non-weak. Over the 254-image closure this moves exactly two symbols out of `missing` across five
  import sites (**66 -> 61**), adds none, and the only image whose import list changes is
  `libswiftFoundation.dylib` itself. One ladder run, both workloads: **XCB_RC=132** in both (the
  standing abort/SIGILL gap), harness VERDICT FAIL, no artifact; the DVTSmartSearch stop line is gone
  (0 hits for `contentsOf`, `folding`, `lengthOfBytes` or `DataTaskPublisher` in either guest log or
  either harness log) and the loader now stops at
  `_$s10Foundation11JSONDecoderC11allowsJSON5SbvsTj`, referenced from
  `…/SharedFrameworks/CoreDocumentation.framework/Versions/A/CoreDocumentation` -- the next rung.

## CoreDocumentation's six Foundation demands, and `JSONDecoder.allowsJSON5` (the allowsJSON5 rung)

- **What the rung is.** `CoreDocumentation` (Xcode 26.3,
  `Contents/SharedFrameworks/CoreDocumentation.framework/Versions/A/CoreDocumentation`, reached
  through `DNTDocumentationModel`'s loader closure) is the demanding image of the contentsOf-URL
  rung's run. It is a chained-fixups image with **2774 binds**, every one against a named component,
  and **eight** unmet, in **two** components: **six** in the **Foundation** field (ordinal 1) and
  **two** in **CryptoKit** (`SHA512`'s type metadata and its `HashFunction` conformance -- a
  different field, and not this rung's). Every other component it binds resolves 100%: swiftCore
  2052, libobjc 281, libSystem 98, libswiftDispatch 32, libswiftos 21, CoreFoundation 5,
  libswiftDarwin 5, libswiftUniformTypeIdentifiers 5, libswift_Concurrency 2. The six Foundation
  names are, in the image's own decoded bind order:

  | walk | segment | symbol | meaning |
  |---|---|---|---|
  | #11 | `__DATA_CONST` p1 | `_$s10Foundation11JSONDecoderC11allowsJSON5SbvsTj` | `JSONDecoder.allowsJSON5` setter (dispatch thunk) |
  | #67 | `__DATA_CONST` p1 | `_$s10Foundation13URLComponentsV11rangeOfPathSnySS5IndexVGSgvg` | `URLComponents.rangeOfPath` getter |
  | #68 | `__DATA_CONST` p1 | `_$s10Foundation13URLComponentsV15rangeOfFragmentSnySS5IndexVGSgvg` | `URLComponents.rangeOfFragment` getter |
  | #142 | `__DATA_CONST` p1 | `_$s10Foundation3URLV18dataRepresentation10relativeTo10isAbsoluteACSgAA4DataVh_AGhSbtcfC` | `URL.init?(dataRepresentation:relativeTo:isAbsolute:)` |
  | #210 | `__DATA_CONST` p1 | `_$sSS10FoundationE10contentsOf8encodingSSAA3URLVh_SSAAE8EncodingVtKcfC` | `String.init(contentsOf:encoding:) throws` |
  | #243 | `__DATA_CONST` p1 | `_$sSy10FoundationE9appendingySSqd__SyRd__lF` | `StringProtocol.appending(_:)` |

  All are strong and eager; the format has no lazy binds, so walk #11 is the loader's stop line.
  The list this rung's prompt carried also named `POSIXError.*` -- that is **not** in this image's
  unmet set (it belongs to `DNTDocumentationSupport`), and it is not taken here.

- **`JSONDecoder.allowsJSON5` is a flag with semantics, not a bridge.** The overlay's `JSONDecoder`
  is the release/5.4 Darwin overlay's (`Foundation/JSONEncoder.swift`), and it read the payload with
  `_JSONSerialization.object(with:)` -- an RFC 8259 parser (`Foundation/JSONSerialization+Swift.swift`)
  -- and carried no JSON5 handling at all. Measured client use (CoreDocumentation's x86_64 slice,
  disassembled around the stub the bind names): one call site, `0x86811` in
  `Markdown.HTMLFormatter.visitInlineAttributes(_:)`, which is swift-markdown's
  `HTMLFormatter.visitInlineAttributes` (upstream `Sources/Markdown/Walker/Walkers/HTMLFormatter.swift:290-319`).
  It builds `"{\(attributes.attributes)}"`, takes `.data(using: .utf8)`, creates a `JSONDecoder`,
  executes `decoder.allowsJSON5 = true` (`movl $0x1,%edi` then the setter thunk), and calls
  `decode(_:from:)` for `struct ParsedAttributes { var \`class\`: String }`. The attributes text is
  documented as JSON5 (`InlineAttributes.attributes`, upstream
  `Sources/Markdown/Inline Nodes/Inline Containers/InlineAttributes.swift`), so the normal input is
  `{class: "foo"}` -- an **unquoted key**, which strict JSON rejects. Storing the flag and parsing
  JSON5 as plain JSON would silently drop the `class` attribute from the rendered HTML (the decode
  is `try?`), i.e. a plausible wrong answer. **The flag is therefore honoured for real**: the reader
  gained a JSON5 mode (`object(with:json5:)`) covering comments, unquoted keys, single-quoted
  strings, trailing commas, the JSON5 escapes (`\v`, `\0`, `\xHH`, line continuations) and the JSON5
  number forms (`+`/`-`, hex, `Infinity`/`NaN`, leading/trailing decimal point, leading zeros). It
  It never falls back to JSON's grammar: anything it cannot read throws `Error.invalidJSON`, so JSON5
  input is either decoded to the value JSON5 defines or fails loudly. With `allowsJSON5 == false`
  the reader is RFC 8259 exactly as before (the mode is a parameter, not a rewrite). The reader was
  exercised host-side against the same file (the parser compiled with the Linux toolchain and
  Foundation, driven through `object(with:json5:)`): strict input still rejects unquoted keys,
  single-quoted strings, trailing commas and `\v`; the client's `{class: "foo"}`, comments, trailing
  commas, `\x`/`\u`/`\v`/`\0` escapes, line continuations and the JSON5 number forms all decode to
  the JSON5 values; and malformed input (unterminated comment/string, `{1abc: 1}`, `{a: tru}`,
  `{a: 1,,}`) fails. That run also caught two strict-mode regressions in the first draft -- a
  `where json5` on a multi-pattern `case` applies only to the last pattern, which had let `+`, `.`
  and `I` (and a backslash before a line terminator) through in strict mode -- which are fixed by
  hoisting the condition into the case body.

- **Per symbol: route and reason.**
  - `JSONDecoder.allowsJSON5` (`open var allowsJSON5: Bool = false`, `Foundation/JSONEncoder.swift`,
    `@available(macOS 12.0, ...)` per `Foundation.swiftinterface:11977`) and the JSON5 reader
    (`Foundation/JSONSerialization+Swift.swift`). `decode(_:from:)` now passes `json5: allowsJSON5`.
  - `URLComponents.rangeOfPath` / `rangeOfFragment` (`Foundation/URLComponents.swift`). Declarations:
    `Foundation.swiftinterface:16871,16883`. In-tree route
    (`swift-corelibs-foundation/Sources/Foundation/URLComponents.swift:237-254`) asks `NSURLComponents`
    for an `NSRange` and converts it with `String.Index(utf16Offset:in:)`; this value type is not
    built on `NSURLComponents` (see the file header), so the range is computed from the stored
    components over the same `string` the getter's `NSRange` would index. Every stored component is
    ASCII (the parser and the setters admit only the RFC 3986 ASCII sets and percent escapes), so a
    UTF-16 offset is exact, and the zero-length-component cases (empty path, empty query, empty
    fragment) match the documented behaviour.
  - `URL.init?(dataRepresentation:relativeTo:isAbsolute:)` (`Foundation/URL.swift`). Declaration:
    `Foundation.swiftinterface:16349`. In-tree route
    (`swift-corelibs-foundation/Sources/Foundation/URL.swift:541-548`) wraps
    `NSURL(dataRepresentation:relativeTo:)` / `absoluteURLWithDataRepresentation:relativeTo:`, which
    are `CFURLCreateWithBytes` / `CFURLCreateAbsoluteURLWithBytes`
    (`submodules/swift-corelibs-foundation/CoreFoundation/URL.subproj/CFURL.c:2471,2537`). Darling's
    `NSURL` declares neither initializer, so those CFURL functions are called directly. Measured
    client use: five call sites, all in `SymbolKit.SymbolGraph.{LineList,Symbol.Location}.url` getters
    (e.g. `0xca07f`), all `URL(dataRepresentation: Data(uri.utf8), relativeTo: nil)` with
    `isAbsolute = 0`; upstream `swift-docc-symbolkit/Sources/SymbolKit/SymbolGraph/Symbol/Location.swift:33-39`
    says the point is to accept URI strings that are not valid URL strings **without escaping or
    processing them** -- which is exactly what `CFURLCreateWithBytes` does (its bytes round-trip
    through `CFURLGetBytes`), so a `URL(string:)` route that escaped or rejected the URI would be a
    wrong value.
  - `String.init(contentsOf:encoding:)` (`Foundation/NSStringAPI.swift`). Declaration:
    `Foundation.swiftinterface:15520`. Body verbatim from the release/5.4 Darwin overlay and
    `swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:384-390`:
    `try NSString(contentsOf: url, encoding: enc.rawValue)` over Darling's own
    `-[NSString initWithContentsOfURL:encoding:error:]` -- a real read decoded with the given
    encoding. A URL that cannot be read, or whose bytes are not valid in that encoding, **throws**
    the `NSError` that initializer produced rather than returning a wrong string. Measured client
    use: five call sites, all `String(contentsOf: url, encoding: .utf8)`.
  - `StringProtocol.appending(_:)` (`Foundation/NSStringAPI.swift`). Declaration:
    `Foundation.swiftinterface:22728`, whose inlinable body the interface carries as
    `var result = String(self); result.append(contentsOf: other); return result`; that body is used
    verbatim (real concatenation, no bridge to defer to). Measured client use: one call site,
    `0x6cc8a9` in `SwiftDocC.StringProtocol.appendingTrailingSlash`, appending a one-character `"/"`;
    the result is the function's return value.

- **Artifact and measured result.** `libswiftFoundation.dylib` sha256
  `5addd4052b770a3341a7bae1660a0bda12eb1ad0bcdf4a5da69867c4fbee3c56` (x86_64-only; built = payload =
  staged = **both** deployed prefix roots = both receipt rows). Built with
  `DARLING_SWIFT_FOUNDATION_ONLY=1 sh overlays/build-arch.sh` (offline; the focused path exits before
  build-arch.sh's bottom copy-into-payload loop, so the built dylib is copied into the payload
  afterwards), deployed with `cmake --regenerate-during-build` plus `west darling-bootstrap` (real
  build). The focused run also rebuilds `Combine.framework/Versions/A/Combine`; that rewrite is
  byte-identical (`a7ae9b16...` before and after), so nothing about the Combine rung's artifact
  changed and it is not restored. The deployed export trie goes **8361 -> 8375 names**, **0 removed /
  14 added** -- the six demanded names plus `allowsJSON5`'s accessor/thunk/metadata and the
  `rangeOf*` property metadata. `CoreDocumentation`'s whole bind table re-decoded against the
  deployed tries: the Foundation field goes **262 binds, 6 unmet -> 0 unmet**; the only remaining
  unmet binds are the two CryptoKit `SHA512` names (a different field). Over the 254-image closure
  this moves exactly eight import sites out of `missing` (the graph's own count is **61 -> 50**; the
  other three sites are CoreFoundation globals a concurrent `src/external/corefoundation` change
  provided, not this rung's), adds none, and removes no name any image imports. One ladder run, both workloads: **XCB_RC=132** in both (the standing
  abort/SIGILL gap), harness VERDICT FAIL, no artifact; the CoreDocumentation Foundation stop line is
  gone (0 hits for `allowsJSON5`, `rangeOfPath`, `rangeOfFragment`, `dataRepresentation`,
  `contentsOf8encoding` or `appending` in either guest log or either harness log) and the loader now
  stops at `_$s9CryptoKit6SHA512VAA12HashFunctionAAMc`, referenced from the same CoreDocumentation
  image -- the CryptoKit field, the next rung.

## DNTDocumentationSupport's `POSIXError` conformance (the posixerror rung)

`overlays/Foundation/POSIXError.swift` is new and is the only source change. It declares
`public struct POSIXError : _BridgedStoredNSError` (`_nsError`, `init(_nsError:)`, `errorDomain` =
`NSPOSIXErrorDomain`, `typealias Code = POSIXErrorCode`) and `extension POSIXErrorCode :
_ErrorCodeProtocol { typealias _ErrorType = POSIXError }`, from release/5.4
`stdlib/public/Darwin/Foundation/NSError.swift` with the `POSIXErrorCode` half left alone: that enum
is `Darwin.POSIXErrorCode`, already declared by the payload's own Darwin overlay and exported by the
deployed `/usr/lib/swift/libswiftDarwin.dylib`. The static code table (`POSIXError.EPERM`, ...) is
**not** included -- the same choice `CocoaError.swift` above documents, and nothing in the closure
binds it.

The demand, measured from the demanding image's own `LC_DYLD_CHAINED_FIXUPS`: DNTDocumentationSupport
imports exactly three Foundation-field names for this type -- the conformance descriptor (bind
#1029, `__DATA_CONST` 0x251300), the metadata accessor (#1030, 0x251308) and the nominal type
descriptor (#1031, 0x251310), all eager and strong -- and `Darwin.POSIXErrorCode.init(rawValue:)`
(#1772, 0x252a38, libswiftDarwin). The demanding code is that image's own
`URL.setExtendedAttribute(named:value:)` / `URL.extendedAttribute(named:)` family: it builds
`POSIXErrorCode(rawValue: errno)`, instantiates the concrete metadata for
`(attributeName: String, returnCode: Int, underlyingError: POSIXError)`, and **calls the
`_BridgedStoredNSError` protocol extension's `init(_:userInfo:)`** with the POSIXError metadata in
`%rsi` and this conformance descriptor in `%rdx` -- so the conformance is dispatched through, and a
descriptor that did not describe a real conformance would hand the client a garbage witness table.

Measured after the deploy: 21 new export-trie names (0 removed) in both prefix roots; the demanding
image's whole POSIXError bind table resolves; a pre-linked client built against this module's own
`Foundation.swiftmodule` and linked to the **deployed** `Foundation.framework` runs inside the guest
and answers the domain, the errno, `errorCode`, `code`, `userInfo`, `NS...Error` bridging both ways,
`_ErrorCodeProtocol`'s `~=`, and the wrong-domain refusal, all correctly (16 checks; the two that
fail are `==`/`hashValue` between two equal `POSIXError`s -- and the same two fail for `NSError`,
`CocoaError` and `URLError`, i.e. a pre-existing value-equality gap in the tree's
`NSError`/`CFEqual` path, inherited by every bridged error type and binding nothing here).

## The payload queue: normalization, list formatting, and IDEFoundation's Foundation field (the payloadqueue2 rung)

This rung worked down the load-time queue the posixerror rung left. It landed, in the same
`libswiftFoundation.dylib`:

- **`StringProtocol.decomposedStringWithCanonicalMapping`** (`overlays/Foundation/NSStringAPI.swift`),
  the rung's live stop line, demanded by `DNTDocumentationSupport`. The body is the one line over
  Darling's own `-[NSString decomposedStringWithCanonicalMapping]`
  (`src/external/foundation/src/NSString.m:1777`, a real `CFStringNormalize` to
  `kCFStringNormalizationFormD`), beside the existing compatibility-mapping sibling. The demanding
  image's own `LC_DYLD_CHAINED_FIXUPS` binds it once, eagerly and strongly (walk #1205,
  `__DATA_CONST` page 2, Foundation ordinal 11).
- **`Foundation.ListFormatStyle`, `Foundation.StringStyle` and their `Sequence.formatted` /
  `FormatStyle.list` extensions**, demanded by `XCStringsParser` (10 names). The source is
  swift-foundation's own `Formatting/ListFormatStyle.swift` and `Formatting/ICUListFormatter.swift`,
  now listed in `build-arch.sh`'s `UPSTREAM_INTL_FILES` and compiled unmodified. `ICUListFormatter`
  is ICU-backed over Darling's ICU 66.1, whose `ulistfmt_openForType` / `ulistfmt_format` /
  `ulistfmt_close` are exported by the deployed `libicucore.A.dylib`; the shim already included
  `<unicode/ulistformatter.h>`.
- **`String.init(contentsOf:usedEncoding:)`, `String.init?(utf8String:)` and
  `StringProtocol.paragraphRange(for:)`** (`NSStringAPI.swift`), **`URLResourceValues.isHidden` and
  `.contentModificationDate`** (`URLResourceValues.swift`), **`URL.removeCachedResourceValue(forKey:)`**
  (`URL.swift`) and **`NSCoder.decodeArrayOfObjects(ofClass:forKey:)`** (`NSCoder.swift`), all
  demanded by `IDEFoundation` (and `utf8String` also by `AppThinning`). Every body rides on real tree
  machinery: `-[NSString initWithContentsOfURL:usedEncoding:error:]` (`NSString.m:990`),
  `-[NSString initWithUTF8String:]` (`NSString.m:735`), `-[NSString paragraphRangeForRange:]`
  (`NSString.m:1615`), `NSURLIsHiddenKey`/`NSURLContentModificationDateKey`
  (`src/external/corefoundation/NSURL.m:277,319`), and `-decodeObjectOfClasses:forKey:`. The two
  that cannot be a call into the tree are stated where they live: `removeCachedResourceValue` is the
  identity because this tree's NSURL keeps no resource-value cache (every query re-`stat`s), and
  `decodeArrayOfObjects` applies Apple's `[NSArray, elementClass]` whitelist through the
  `-decodeObjectOfClasses:forKey:` this tree does have.
- **`RunLoop : Combine.Scheduler`** (`overlays/Foundation/Schedulers+RunLoop.swift`, new), demanded by
  `IDEFoundation` (5 names). It is the release/5.4 Darwin overlay's source verbatim except where
  Darling's SDK imports the ObjC surface differently: `-[NSTimer
  initWithFireDate:interval:repeats:block:]` imports as a failable initializer and `-tolerance` as a
  method pair, so the repeating-schedule body unwraps once and calls `setTolerance(_:)`; the
  immediate and delayed schedules use `RunLoop.perform(_:)` and `perform(_:with:afterDelay:)`.

Not reached, and why: `StringProtocol.applyingTransform(_:reverse:)` needs the Clang type
`NSStringTransform`, which Darling's `Foundation/NSString.h` (and so its SDK) does not declare --
the symbol's parameter mangles as `__C.NSStringTransform` and cannot be produced from a shim.
(All three were landed by the next rung: see "The last three payload blockers" below.)
`SortDescriptor`, `String.StandardComparator` and `Sequence.sorted(using:)` are swift-foundation's
`FOUNDATION_FRAMEWORK`-guarded API (`String.StandardComparator.localizedStandard` and
`SortDescriptor`'s default arguments only exist under that define), and turning the define on breaks
`ICUDateFormatter.swift` (`Locale.customDateFormat`), `NumberFormatStyleConfiguration.swift`
(`Formatter.Context`) and `ICUNumberFormatter.swift` in the currently built set. The
`libswiftDispatch` `OS_dispatch_queue : Combine.Scheduler` conformance needs Combine built before
Dispatch (the Dispatch overlay would `import Combine`), which is a full-build reordering; and
`NSData : Swift.Sequence` is an inherited-conformance descriptor the compiler does not emit for a
`DataProtocol` conformance here.

## The last three payload blockers: `NSData : Sequence`, the SortDescriptor family, and the Dispatch scheduler (the payload-blockers rung)

This rung closed the three items the payload queue had to leave open, plus
`StringProtocol.applyingTransform(_:reverse:)`, whose blocker was the header gap the NSStringTransform
rung closed. All three live in `libswiftFoundation.dylib` except the Dispatch one.

- **`NSData : DataProtocol`** (`overlays/Foundation/NSData+DataProtocol.swift`, new), demanded by
  `IDEDistribution`, which binds the *inherited* `__C.NSData : Swift.Sequence` descriptor
  (`_$sSo6NSDataCST10FoundationMc`). The bodies are swift-corelibs-foundation's own
  (`Sources/Foundation/NSData+DataProtocol.swift`) with `enumerateBytes` replaced by direct
  `bytes`/`length` access, because this overlay declares no Swift `enumerateBytes` on NSData. Declaring
  the one conformance emits the whole inherited closure, which is what Apple's own tbd lists
  (`…DataProtocolACMc`, `…SK…`, `…ST…`, `…Sk…`, `…Sl…`) -- there is no separate `NSData : Sequence`
  to write, and Swift refuses the redundant one.
- **`SortDescriptor`, `String.StandardComparator` and `Sequence.sorted(using:)`**, demanded by
  `IDEFoundation` (6 names; `SortDescriptorVMn` was the rung's starting live stop). The API is
  swift-foundation's, guarded by `#if FOUNDATION_FRAMEWORK`, and the define cannot be module-wide:
  it breaks `ICUDateFormatter.swift` (`Locale.customDateFormat`),
  `NumberFormatStyleConfiguration.swift` (`Formatter.Context`) and `ICUNumberFormatter.swift`. So
  `build-arch.sh` takes **copies** of just the two files that carry the API
  (`FoundationInternationalization/String/SortDescriptor.swift` and `String+SortComparator.swift`),
  renames the guard in them to `DARLING_FOUNDATION_FRAMEWORK` with `sed`, and passes that define to
  the module build; the checkout is never written to (`$out/darling-foundation-darwin` holds the
  copies). `SortComparator.swift` joins `UPSTREAM_FILES` unmodified, which is where `SortComparator`,
  `SortOrder`, `AnySortComparator` and `Sequence.sorted(using:)` come from.
  `overlays/Foundation/KeyPath+Sendable.swift` (new) carries the one `package` declaration those
  files need that swift-foundation keeps in `Predicate/PredicateExpression.swift` -- a file this
  overlay does not build -- with upstream's body.
- **`StringProtocol.applyingTransform(_:reverse:)`** (`overlays/Foundation/NSStringAPI.swift`),
  demanded by `IDEFoundation`. Its parameter is the `NSStringTransform` typedef, now declared in
  `src/external/foundation/include/Foundation/NSString.h` by the NSStringTransform rung and mapped to
  Swift `StringTransform` by a new `Foundation.apinotes` `Typedefs` entry (Apple's own apinotes has
  exactly that entry). The body calls `CFStringTransform`, the tree's own ICU transliterator, because
  the tree's ObjC `NSString` has no `-stringByApplyingTransform:reverse:` to delegate to; nil means
  what Apple's means (invalid identifier or irreversible reverse).
- **`extension DispatchQueue : Combine.Scheduler`** (`overlays/Dispatch/Scheduler.swift`, new),
  demanded by `IDEFoundation` (3 names: the conformance descriptor and `SchedulerOptions`' metadata
  and nominal descriptors, which must come from `libswiftDispatch.dylib`). The declarations are the
  guest SDK's `Dispatch.swiftinterface` lines 529-610 and the bodies are OpenCombine's own
  `OpenCombineDispatch/DispatchQueue+Scheduler.swift` (the pinned `10df981` checkout) re-nested from
  its `OCombine` namespace onto `DispatchQueue`; OpenCombine's `Stride.*` stub returns zero and is
  replaced by the clamped product the conversions in the same file use. `build-arch.sh` links the
  Dispatch module **twice**: in its usual place before Combine (where `-D DARLING_DISPATCH_COMBINE`
  is absent, so the file is empty) and again right after the Combine block, with the define and the
  Combine binary, which is the link that ships. `canImport(Combine)` cannot be the gate -- $out/modules
  keeps the previous build's `Combine.swiftmodule`, so the earlier link would compile the conformance
  and fail to resolve Combine's protocol descriptors. Reordering the two modules instead would move
  the focused-path exits, which must stay before Combine. A `DARLING_SWIFT_DISPATCH_ONLY` focused exit
  sits after the second link, the same shape as `NETWORK_ONLY`/`COMBINE_ONLY`.
- **Two SDK-surface corrections** in `src/external/foundation/include/Foundation/`: `NSSortDescriptor`'s
  `key`, `ascending` and `selector` are declared as Apple declares them (readonly properties, `key`
  and `selector` nullable) -- the SortDescriptor guards read them as properties -- and
  `Foundation.apinotes` gains Apple's `NSStringTransform` → `StringTransform` entry.

## IDESimulatorFoundation's `URL.homeDirectory` (the Xcode-system-resources rung)

- **What the rung is.** With `CoreSimulator` deployed, the whole-demand enumeration of Xcode 26.3's
  `Contents/Frameworks/IDESimulatorFoundation.framework/Versions/A/IDESimulatorFoundation` (sha256
  `83db461982c7f9846adf4a160baaa6b6d73925852a3d3f2429d6756b84873c0f`) reports exactly one unmet
  Foundation-field member and one unmet CoreSimulator-field member. This is the first of the two:

  ```
  Symbol not found: _$s10Foundation3URLV13homeDirectoryACvgZ
    Referenced from: .../IDESimulatorFoundation.framework/Versions/A/IDESimulatorFoundation
    Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
  ```

  `Foundation.framework` re-exports `/usr/lib/swift/libswiftFoundation.dylib` as an ordinal, so the
  name is reachable under the image the loader names; the member is the overlay's.

- **Declaration.** The guest SDK's `Foundation.swiftinterface` (x86_64 slice) line 16588, inside its
  `extension Foundation.URL`, `@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)`:
  `public static var homeDirectory: Foundation.URL { get }`. The mangled getter is
  `_$s10Foundation3URLV13homeDirectoryACvgZ`.

- **Body: Apple's own, over this tree's own home-directory primitive.** swift-foundation's
  `Sources/FoundationEssentials/URL/URL.swift:1573` (the checkout the build fetches, commit
  `dbacc67`, tag `swift-6.3-DEVELOPMENT-SNAPSHOT-2026-06-07-a`) has three arms: with
  `FOUNDATION_FRAMEWORK && !os(macOS)` it is `URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)`;
  with `FOUNDATION_FRAMEWORK` on macOS it is `FileManager.default.homeDirectoryForCurrentUser` when
  `foundation_swift_url_enabled()`, else `URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)`;
  otherwise `FileManager.default.homeDirectoryForCurrentUser`. This overlay is the macOS framework
  case, and `FileManager.homeDirectoryForCurrentUser` exists nowhere in this tree
  (`grep -rn homeDirectoryForCurrentUser src/external/swift/overlays/Foundation/` finds only the
  never-compiled swift-foundation checkout, and the overlay's `FileManager.swift` does not declare
  it), so the written-out arm is the `NSHomeDirectory()` one, which this tree does implement:
  `src/external/foundation/src/NSPathUtilities.m:389` returns the `HOME` environment value and
  falls back to `/`. `DirectoryHint.isDirectory` supplies the trailing `/` Apple's `~/` form
  implies, exactly as Apple's body does. The file's own `init(filePath:directoryHint:relativeTo:)`
  (line 478) is the constructor this compiles against, and `NSHomeDirectory()` is visible to the
  overlay because the SDK's `Foundation.h:51` imports `NSPathUtilities.h`.

- **What is deliberately not written.** The sibling standard-directory properties the same SDK
  extension declares (`temporaryDirectory`, `cachesDirectory`, `documentsDirectory`, ...) and the
  `homeDirectory(forUser:)` overload: no image in this load closure demands them, and each would
  need its own measured body. The enumeration is the worklist, as it has been for every rung of
  this file.

## SWBUtil's eleven Foundation symbols (the next-stops-behind-ArgumentParserInternal rung)

- **What the rung is.** Xcode 26.3's build-system plug-in `com.apple.dt.IDEXCBuildSupportCore` cannot
  load because `SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/Frameworks/SWBUtil.framework/Versions/A/SWBUtil`
  binds strong eager symbols from the Foundation field, and the coverage model (the wave's
  `closure_analyze.py --cover`, recorded in
  `evidence/new-build-system-rung/analysis/next-stops-behind-argumentparserinternal.txt`) labels eleven of
  them `missing` -- absent from the field image, from its re-export chain and from every image the process
  loads, so dyld aborts on whichever one it reaches first as soon as the `ArgumentParserInternal` image
  above exists.  All eleven were measured exported by no image in the deployed prefix (`grep` over the
  deployed trees' symbol tables: 0 hits) before this rung.  A sibling rung owns the nine
  `libswiftAppleArchive` names of the same list; these eleven are the Foundation group, and the payload queue
  below is where most of them were first predicted.

- **`URLResourceValues.isExcludedFromBackup`** (`Foundation/URLResourceValues.swift`) -- declaration: the
  guest SDK's `Foundation.swiftinterface:15841`, `public var isExcludedFromBackup: Swift.Bool? { get set }`;
  the two manglings are `_…V20isExcludedFromBackupSbSgvg` and `…SbSgvs`.  Body: **Apple's own open source**
  for this module, corelibs `Sources/Foundation/URL.swift:223-226` over a new `_set(_:newValue:Bool?)` copied
  from the same file's lines 68-76.  Real: the getter asks the same resource-value machinery as this file's
  other properties, and the setter records the value for `URL.setResourceValues(_:)`.  What that machinery
  answers for this key is read from the tree's own sources, not assumed: `-resourceValuesForKeys:error:`
  (`src/external/corefoundation/NSURL.m:1105`) returns `kCFBooleanTrue` for it unconditionally
  (`NSURL.m:494-497`), and `-setResourceValues:error:` (`NSURL.m:1115-1118`) accepts a CFBoolean for it and
  keeps it in the URL's resource info (`NSURL.m:949`, `:892-894`), which the getter then reads back.  The
  round trip through one URL object is therefore real, and no FS-level backup exclusion is claimed.

- **`URL.setResourceValues(_:)`** (`Foundation/URLResourceValues.swift`, in the `extension URL` the file
  already has) -- declaration: `Foundation.swiftinterface:16537`, `public mutating func setResourceValues(_
  values: Foundation.URLResourceValues) throws`; mangling `_…V17setResourceValuesyyAA011URLResourceE0VKF`.
  Body: **Apple's own open source**, corelibs `Sources/Foundation/URL.swift:923-925` (`try
  _writableURL.setResourceValues(values._values)`), reached here through this file's existing
  `_bridgeToObjectiveC()` (the receiver is the NSURL the `URL` struct wraps) so a write lands on the same
  NSURL object a later `resourceValues(forKeys:)` reads.  Which values are written is corelibs' own answer:
  the whole dictionary the struct carries, not a filter invented here.

- **`DispatchData.Region` and `DispatchData.regions`** (`Foundation/DataProtocol.swift`, appended as the
  file's DispatchData conformance; the file gains `import Dispatch`) -- declarations:
  `Foundation.swiftinterface:20860-20893`, `extension Dispatch.DispatchData : Foundation.DataProtocol`, the
  nested `public struct Region : Foundation.DataProtocol, Foundation.ContiguousBytes` and `public var regions:
  [Dispatch.DispatchData.Region] { get }`.  Body: **Apple's own open source**, corelibs
  `Sources/Foundation/DispatchData+DataProtocol.swift` (the whole file, nothing reduced), over this tree's
  `DispatchData` (`overlays/Dispatch/Data.swift`, whose `Index` is `Int` and which hands each contiguous
  range to `enumerateBytes`).  Five of the demanded names are this: the `DataProtocol` conformance
  descriptor, the `ContiguousBytes` witness table, `Region`'s metadata accessor and nominal descriptor, and
  the `regions` getter.  One deliberate difference: the SDK also declares `Region : Sendable`
  (`Foundation.swiftinterface:20861`) and that conformance is **not** written here, because this tree's
  `DispatchData` (a struct around an unmanaged `__DispatchData`) is not `Sendable` and `Region` stores one;
  nothing in the demanded set involves `Sendable`.  The eleven plus their companions add 33 exports in total.

- **`NSFileHandle.offset()`** (`Foundation/NSFileHandle.swift`, beside the file's other descriptor-surface
  members) -- declaration: `Foundation.swiftinterface:493`, `@available(macOS 10.15.4, …)`, `public func
  offset() throws -> Swift.UInt64`.  Body: **Apple's own open source**, corelibs
  `Sources/Foundation/FileHandle.swift:517-533` -- POSIX `lseek(_fd, 0, SEEK_CUR)`, the null device answered
  with 0, the failing errno reported through this file's `_FileHandleReadError`.  Real: the offset is read
  from the descriptor the class's Objective-C surface hands over.  The file's own "what is still not" list
  said a later rung would add this here when a client measured it; this is that rung, and the list is updated.

- **`NSFileManager.replaceItemAt(_:withItemAt:backupItemName:options:)`** (`Foundation/FileManager.swift`)
  -- declaration: `Foundation.swiftinterface:476` (the `@available(swift 4)` overload returning
  `Foundation.URL?`; mangling `_$sSo13NSFileManagerC10FoundationE13replaceItemAt_04witheF006backupE4Name7optionsAC3URLVSgAI_AISSSgSo0abE18ReplacementOptionsVtKF`).
  This one is **not a bridge**: Darling's `NSFileManager` declares
  `-replaceItemAtURL:withItemAtURL:backupItemName:options:resultingItemURL:error:`
  (include/Foundation/NSFileManager.h:161) and implements it nowhere in `src/external/foundation/src`, and
  `_CFURLReplaceObject` (CoreFoundation's underlying implementation) is likewise absent, so the file carries
  the algorithm.  Body: **Apple's own open source**, corelibs
  `Sources/Foundation/FileManager+POSIX.swift:1219-1341` (the implementation its Swift-declared
  `replaceItemAt`, `FileManager.swift:1123-1125`, calls), ported with three measured platform facts:
  corelibs' test-only `allowPlatformSpecificSyscalls` switch is dropped; the platform block keeps its Darwin
  arm (`renameatx_np` + `RENAME_SWAP`, declared in the SDK's `sys/stdio.h:48` and exported by the deployed
  `libsystem_kernel` -- `llvm-nm`: `T _renameatx_np`); and that arm's fall-through set gains `EINVAL`,
  because a guest's file system calls ARE the host's (the deployed `libsystem_kernel`'s
  `bsdsyscalls___renameatx_np` loads XNU's number `$0x1e8` and enters `__darling_bsd_syscall`, and Linux
  answers EINVAL rather than ENOTSUP for a filesystem without `RENAME_EXCHANGE`), which is also what
  corelibs' own Glibc arm says (`FileManager+POSIX.swift:1299`).  The attributes the default options
  preserve go through the tree's `attributesOfItem(atPath:)`/`setAttributes(_:ofItemAtPath:)` with the SDK's
  `NSFileType`/`NSFileCreationDate`/`NSFilePosixPermissions` strings, because this tree declares no
  `NSFileAttributeKey` typedef and therefore no `FileAttributeKey`.

- **`StringProtocol.precomposedStringWithCanonicalMapping`** (`Foundation/NSStringAPI.swift`, beside the Form
  D sibling) -- declaration: `Foundation.swiftinterface:22711`.  Body: **Apple's own open source**,
  corelibs `Sources/Foundation/NSStringAPI.swift:1060-1065`, which is the one-line bridge to `_ns`.  There is
  a **known defect underneath, named rather than hidden**: Darling's
  `-[NSString precomposedStringWithCanonicalMapping]` (`src/external/foundation/src/NSString.m:1801-1807`)
  normalizes with `kCFStringNormalizationFormKD` where the name and Apple promise Form C (that file's
  `decomposedStringWithCompatibilityMapping` carries Form C for the same reason).  The bridge is still the
  truthful implementation -- a client that calls the Objective-C method and one that calls this property must
  not get different answers -- and the correction belongs in `src/external/foundation`, not in this overlay.

- **Artifact and measured result.** Built with the existing focused path, which is the whole build minus the
  other dylibs: `DARLING_SWIFT_FOUNDATION_ONLY=1 sh overlays/build-arch.sh` under the environment
  `state/nsfilehandle-rung/build-foundation-overlay.sh` sets (Swift 6.3.1 Linux toolchain, Darling's SDK,
  `x86_64-apple-macosx26.0`).  The payload copy
  `src/external/swift/libswiftFoundation.dylib` is that build's output: sha256
  `1fa60063b9088c60f45caa92474fba788ea1fff8f8184fa3bb04f431b0baf4f7`, 8,241,140 bytes, install name
  `/usr/lib/swift/libswiftFoundation.dylib`.  `llvm-nm --defined-only -g` reports 8,812 exported symbols
  against 8,779 before: **+33, with the removal direction empty** -- every name the old dylib exported is
  still exported, and the thirty-three additions are the eleven above plus their companions (property
  accessors and property descriptors, `Region`'s member accessors, its four collection-conformance
  descriptors and its nominal-descriptor `N`, the two witness tables the demanded set does not itself name
  -- `Region`'s `DataProtocol` witness table and `DispatchData`'s own conformance pair -- and the
  subscript/`startIndex`/`endIndex`/`withUnsafeBytes` members `Region` must have to BE a `DataProtocol`).
  Each of the eleven was quoted from `llvm-nm` in the rung's hand-off.

## How the fetched code is built

- **swift-collections is built without library evolution and linked into `libswiftFoundation`.**
  `InternalCollectionsUtilities` and `_RopeModule` are an implementation detail of
  `AttributedString`'s storage, not part of the SDK, so `build.sh` compiles them to objects and
  links those into the Foundation dylib rather than shipping them as dylibs. Apple links
  `CollectionsInternal` into `Foundation.framework` the same way, and hides its symbols, so
  `build.sh` passes ld64 an `-unexported_symbols_list` naming both module prefixes to keep their
  1,159 symbols out of the dylib's export table. Their own sources are unmodified; this is a choice
  about how they are built, not a change to them.

- **`build.sh` passes `-package-name swift-foundation`.** Without it, `package`-level declarations
  such as `LockedState` silently degrade to `fileprivate` and the module does not compile. The value
  matches swift-foundation's own package identity so `package` symbols mangle as upstream does.

## Not built at all, and why

Nothing here is stubbed or approximated. These are left out because no honest source exists in the
tree:

- The `#if FOUNDATION_FRAMEWORK`-guarded parts of the fetched files. The files themselves are
  compiled whole and their unguarded declarations do work, so `AttributeScopes` and
  `FoundationAttributes` exist; what is missing is the guarded half, which is where the attribute
  scope's dynamic registration, `AttributedString`'s `Codable` conformances and
  `AttributedString(NSAttributedString)` live. That mode needs the Clang modules `MachO.dyld`,
  `ReflectionInternal`, `CollectionsInternal` and `Foundation_Private.NSAttributedString`, none of
  which Darling has.
- The ICU-backed `FormatStyle` implementations other than the date, number, byte-count and
  duration styles below (for example `ListFormatStyle` and `Measurement.FormatStyle`), and
  `AttributedString(localized:)`.
- `AttributedString(markdown:)` and `MarkdownParsingOptions`, which need swift-cmark.
- `InlinePresentationIntent`. It is not declared anywhere in swift-foundation, and
  `NSInlinePresentationIntent` is absent from darling-foundation's headers, so there is nothing to
  take. It is not invented here.

## `JSONDecoder.decode(_:from:configuration:)`, the symbol SWBBuildService's Android plug-in stops on

- **What the rung is.** `SWBBuildService.bundle`'s `SWBAndroidPlatformPlugin` is loaded eagerly by
  Xcode 26.3's build service, and its load stops the service before any build traffic. The abort text
  (`evidence/oslog-framework-rung/runs/child-core-999076-dyld-error.txt`) names one symbol, demanded by
  `SWBAndroidPlatform.framework/Versions/A/SWBAndroidPlatform` (built for Mac OS X 14.0), field
  `Foundation` -- whose image is `/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`
  and which re-exports `/usr/lib/swift/libswiftFoundation.dylib` (`LC_REEXPORT_DYLIB`, load command 13):

  ```
  _$s10Foundation11JSONDecoderC6decode_4from13configurationxxm_AA4DataV21DecodingConfigurationQztKAA013DecodableWithH0RzlFTj
  ```

  Demangled with this tree's toolchain (`swift-demangle`), it is the **dispatch thunk** of

  ```
  Foundation.JSONDecoder.decode<A: DecodableWithConfiguration>(_: A.Type, from: Data, configuration: A.DecodingConfiguration) throws -> A
  ```

  i.e. the `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)` entry point Apple's own SDK declares
  (`…/MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/x86_64-apple-macos.swiftinterface:11989`),
  and the same declaration swift-foundation carries at
  `Sources/FoundationEssentials/JSON/JSONDecoder.swift:350`. A `scripts/closure_analyze.py --cover` pass
  over `xcodebuild`, `SWBBuildService` and the plug-in (119 images, 43,006 imports) finds this to be the
  **only** unmet eager demand in that closure.

- **Why it was absent, and why the fix is an addition rather than a replacement.** The overlay's
  `JSONDecoder` is the release/5.4 Darwin overlay's (`Foundation/JSONEncoder.swift:1052`,
  `@_objcRuntimeName(_TtC10Foundation13__JSONDecoder)`), which predates SE-0370's Foundation overlay
  entry points; the file mentioned neither `DecodableWithConfiguration` nor `DecodingConfiguration`.
  The nominal type, its metadata and its Objective-C runtime name are the ones the whole deployed runtime
  already carries, so the correct act is to **extend that declaration**: the compiler then emits the
  demanded thunk, its `Tq`, and the `C.Type` overload's pair as ordinary library-evolution exports. No
  symbol is hand-written, no second `JSONDecoder` exists, and nothing the accepted library exported is
  removed.

- **What was added.** The two entry points Apple declares, with the declarations written as Apple's
  interface writes them, plus one private helper (`_topLevelObject(from:)`) so that the existing
  `decode(_:from:)` and the new ones translate `JSONSerialization`'s parse failure into the same
  `DecodingError.dataCorrupted`. The configuration reaches nested values through the container path
  (`KeyedDecodingContainer.decode(_:forKey:configuration:)` → `superDecoder(forKey:)`), which this
  tree's existing container already implements, so no decoder-side plumbing was needed.

- **Artifact and measured result.** `libswiftFoundation.dylib` sha256
  `5664d6e47239edadc85c7484e97da017a60f4f1f191cefc9c31bbce505ccb4b1` (8,242,028 bytes) ->
  `42a2542e9ef4aafa1759698a9e7e2cbf5c7f11fbae925ca171b3e4fd29013061` (8,243,324 bytes).
  Exported symbols 8814 -> 8818: the **four** added are exactly the demanded thunk, its `Tq`, and the
  `C.Type` overload's `Tj`/`Tq`; `comm -23` against the accepted library is empty, so **nothing was
  removed**. `_$s10Foundation11JSONDecoderCMa`/`CMn`/`CN` remain single definitions, and across the prefix
  the images that define the `JSONDecoder` metadata symbol still hold one distinct content.
  A guest test compiled against the candidate module and linked by install name
  (`guest-test/FoundationConfigDecodeTest`), run twice against the SAME binary with only the two runtime
  copies of the library swapped: **RED** with the accepted library `dyld: Symbol not found` +
  `EXIT=134`; **GREEN** with the candidate `VERDICT passed=13 failed=0` + `EXIT=0` -- plain decoding
  unchanged, two different supplied configurations producing two different results, nested propagation,
  the `DecodingConfigurationProviding` form, and `dataCorrupted` / `typeMismatch` / `keyNotFound` for the
  negative cases.

## `Bool` bridging of a boolean `NSNumber` (the `Unable to bridge NSNumber to Bool` trap)

- **What the rung is.** With the configuration entry points above deployed, the same minimal-project
  workload reaches `CreateBuildRequest` and `SendProjectDescription` -- the build-service session is up --
  and then the guest dies with `XCB_RC=132`:

  ```
  ** INTERNAL ERROR: Uncaught exception **
  Uncaught Exception: NSHashInsertKnownAbsent ... item not absent
  Foundation/NSNumber.swift:215: Fatal error: Unable to bridge NSNumber to Bool
  ```

  `NSNumber.swift:215` is `Bool._forceBridgeFromObjectiveC`, i.e. a client's `as! Bool` on an `NSNumber`.

- **Measured root cause.** The overlay's `Bool.init?(exactly:)` compared against `NSNumber(value: 1)` / `0`
  only (the file's own header said so: "Bool's exact-value check compares against 0/1 instead of
  kCFBooleanTrue/kCFBooleanFalse identity"). On this tree that substitution is **false for every boolean**:
  `NSNumber(value: 1) == kCFBooleanTrue` is `false`, because a boolean-encoded `NSNumber` (`objCType` `"c"`,
  which is what `kCFBooleanTrue`, `@YES`, a JSON `true` and a plist boolean all are) is not equal to an
  integer-encoded one. `Foundation/NSNumberBoolBridgeTest.swift` (guest) measured it shape by shape: with the
  old code **14 pass / 9 fail**, and every failure is a `c`-encoded number -- `@YES`, `@NO`, `kCFBooleanTrue`,
  `kCFBooleanFalse`, JSON `true`/`false`, plist boolean -- each giving `as? Bool` = nil and, forced,
  `Unable to bridge NSNumber to Bool`.

- **What was fixed.** `Bool.init?(exactly:)` now tests the `kCFBooleanTrue`/`kCFBooleanFalse` singletons by
  identity **as well as** the 0/1 value, which is exactly the shape Apple's own Darwin source uses
  (`swift-corelibs-foundation/Darwin/Foundation-swiftoverlay/NSNumber.swift:549-563`). After the fix the same
  test reports **21 pass / 2 fail**, and the two remaining failures are the equality comparison itself, not
  the bridge.

- **Artifact and measured result.** sha256
  `42a2542e9ef4aafa1759698a9e7e2cbf5c7f11fbae925ca171b3e4fd29013061` -> `70691ade83e6324eaf56ce1b66608e303a1e19adb2d4a186ef8ca66429312f5c`.
  Evidence: `evidence/ios-ci-rung/round51/bridge-arm.log` (before), `bridge-after.log` (after),
  `NSNumberBoolBridgeTest.swift`, `guest-test/NSNumberBoolBridgeTest/`.

- **Deliberately NOT changed, and measured.** `NSNumber` equality itself still says
  `NSNumber(value: 1) != kCFBooleanTrue`, where Apple's `isEqual:` treats a boolean and the integer 1 as
  equal. That is a `darling/src/external/foundation` (Objective-C) semantic question with a much wider blast
  radius than this rung -- the Bool bridge does not depend on it any more -- so it is recorded here rather
  than changed in the same commit: the bridge test prints it as an `OBSERVE` line and the owning Bead carries
  it as the follow-up.

## Fixes worth sending upstream
None. Nothing in these two files needed correcting; the only changes are the exclusion above, which
is a statement about Darling's `Calendar` and `TimeZone`, not about swift-foundation.

## Reproducibility

`build.sh` is bit-reproducible when run twice from the same directory: wiping `overlays/build` and
rebuilding produces an identical `libswiftFoundation.dylib`.

It is not reproducible across different build directories. Two builds of the same commit at
different paths give an arm64 slice differing by 26 of 4,110,348 bytes: the 16-byte `LC_UUID`,
which ld64 derives from the content, and five `mov w2, #imm` immediates in `__text` whose values
track the build root's path length exactly (a 41-character root gives 76, an 81-character root 116,
an 83-character root 118). `__swift_modhash` never reaches the dylib; the linker drops it.

This predates the AttributedString work and is not related to whether a dependency is vendored or
fetched. Measured on the tree of #33, which is master plus a CryptoKit framework and contains none
of this branch's changes: built at two different paths, `libswiftFoundation.dylib` differs by 21
bytes and `libswiftDispatch.dylib` by 27, while `Darwin`, `ObjectiveC`, `CoreFoundation`, `os`,
`XPC`, `CoreGraphics`, `AppKit` and `CryptoKit` are all bit-identical.

## StorageKit private-framework provider

The CoreDevice and Xcode build-service load path requires
`/System/Library/PrivateFrameworks/StorageKit.framework/Versions/A/StorageKit`.
`overlays/StorageKit/` is a measured source implementation of the demanded class
and selector subset, backed by the real `hdiutil`/FUSE HFS+ attach path. It is
not a generic StorageKit replacement and not an empty class-name shim.

The build boundary is explicit. `overlays/StorageKit/build.sh` is the supported
provider recipe and writes the image under
`substitutes/System/Library/PrivateFrameworks/StorageKit.framework/Versions/A/`.
Neither `overlays/build.sh` nor `overlays/build-arch.sh` invokes it, and
`swift/CMakeLists.txt` has no StorageKit build target. The superproject's
rootless `substitutes/*` glob can stage a file that is already present, but it
does not create one. A clean checkout therefore does not reproduce the provider
merely through the canonical Swift/CMake orchestration; a fresh-checkout build
and deployment path is still an integration gap, not a property proved by a
manually installed binary. The hdiutil backend is the existing `darling-dmg`
CMake target `hdiutil`; it is separate from the provider recipe.

The provider checks the kernel mount table for both attach and detach. Mount
identity is resolved through Darling's `__darling_vchroot_expand` guest-to-host
path resolver (the same API hdiutil uses), then compared by exact host path;
suffix or prefix-name matching is not accepted. The manager reconciles retained
attachments against the current host table, so an attachment removed by an
external hdiutil does not remain visible after `syncAllDisks`. After a confirmed unmount, a failing mount-directory `rmdir` is
reported as a cleanup warning but does not turn the detach into a fake live
mount; the directory is not recursively removed. APFS, arbitrary UDIF, full
CoreDevice behavior and the iOS application remain outside this scope.
