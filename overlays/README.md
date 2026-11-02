# arm64 Swift SDK overlays

Swift.org toolchains stopped shipping the Darwin SDK overlays, so the copies in this repository were x86_64-only (Swift 5.2.2). `build.sh` builds arm64 slices of ten of them and merges them into the existing universal binaries. The x86_64 slices are unchanged. Four are built from the last open-source Swift sources; `os`, `XPC` and `SceneKit` were never open source, so they are written from Apple's public API documentation and the imported symbol names (no Apple code).
Swift.org toolchains stopped shipping the Darwin SDK overlays, so the copies in this repository were x86_64-only (Swift 5.2.2). `build.sh` builds arm64 slices of ten of them and merges them into the existing universal binaries. The x86_64 slices are unchanged. Four are built from the last open-source Swift sources; `os`, `XPC` and `QuartzCore` were never open source, so they are written from Apple's public API documentation and the imported symbol names (no Apple code).

## Split Darwin overlays

`build-arch.sh` also builds `_DarwinFoundation1`, `_DarwinFoundation2`,
`_DarwinFoundation3`, `_errno`, `_math`, `_stdio`, `_time`, `sys_time`,
`_signal` and `unistd`. These are real Mach-O reexport libraries, not renamed
copies of incompatible Swift modules. The Foundation groups reexport the single
source-built `libswiftDarwin`; the header overlays reexport their corresponding
Foundation group. Swift emits each module's force-load marker using the same
`-autolink-force-load` path as the other overlays. Root-level dylibs are installed
by the existing Swift CMake glob; no prefix-local deployment is needed.
The facade Swift modules are runtime build artifacts only, isolated in
`runtime-modules/` and neither imported by other overlays nor installed as SDK
interfaces. They do not replace the SDK's real source declarations.

The ABI authority is Xcode 26.3's MacOSX SDK: its
`usr/lib/swift/_DarwinFoundation{1,2,3}.swiftmodule/*.swiftinterface` declares
`-module-abi-name Darwin`, and its corresponding `.tbd` files retain the
`$s6Darwin...` symbols. Its header-overlay TBDs declare precisely these
reexport edges. Foundation1 contains errno, POSIX error metadata and math
(including x86_64 Float80); Foundation2 contains stdio and Duration/time
conversions; Foundation3 contains signal constants and the unavailable fork
APIs. Reexporting one genuine provider preserves type-metadata identity and
libc's errno/stdio state across old and split clients.

The vendored provider comes from Swift `release/6.1`'s
[`stdlib/public/Platform`](https://github.com/swiftlang/swift/tree/release/6.1/stdlib/public/Platform).
The newer public
[`main` Platform sources](https://github.com/swiftlang/swift/tree/main/stdlib/public/Platform)
no longer contain the Darwin overlay or its split implementation; the local
read-only VibeDarling reference has no populated Swift overlay source. Thus
the existing real provider is reused rather than importing a second implementation.
The SDK interface and `usr/include/sys/errno.h` additionally require enum values
102 (`_EOPNOTSUPP_UNIX2003`) and 107 (`ENOTCAPABLE`), the EOPNOTSUPP getter
returning the UNIX2003 value on supported x86_64/arm64 targets, and ELAST=107.
These replace the vendored source's unresolved EOPNOTSUPP FIXME and old ELAST.

Focused rebuild: use the normal `build-arch.sh` environment with `DARWIN_ONLY=1`.
An x86_64 rebuild replaces only the Intel slice, preserving an existing arm64
slice; an arm64 rebuild merges with the checked-in x86_64 slice.
Build x86_64 first when introducing both slices of a new library.
For a host cross-build using the canonical local prerequisites:

```sh
export SWIFT_TOOLCHAIN=/home/ilyagulya/work/downloads/swift-linux/swift-6.3.1-RELEASE-ubuntu24.04/usr
export SWIFT_RESOURCE_DIR=/home/ilyagulya/work/local-target/swiftpkg/stage/usr/lib/swift
export DARLING_SDK=/home/ilyagulya/work/wr-fresh/.west-state/cutover-gtci/source/darling/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
export DARLING_LD=/home/ilyagulya/work/wr-fresh/.west-state/cutover-gtci/build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld
export DARLING_ROOT=/home/ilyagulya/work/wr-fresh/.west-state/cutover-gtci/runtime-66/libexec/darling
export DARLING_LIBSYSTEM=/home/ilyagulya/work/wr-fresh/.west-state/cutover-gtci/build/src/external/libsystem/libSystem.B.dylib
export SWIFT_DARWIN_ARCH=x86_64 DARWIN_ONLY=1
export OVERLAY_BUILD_DIR=/home/ilyagulya/work/wr-fresh/.west-state/ios-archive-j17/darwin-split/x86_64-complete
sh overlays/build-arch.sh
```

This uses genuine Darling implementation libraries as link inputs and neither
copies Apple implementation binaries nor modifies an installed image.
`llvm-lipo` must be on PATH (some hosts name it `llvm-lipo-18`).
An arm64 rebuild needs a complete arm64 SDK and arm64 link providers, using
`SWIFT_DARWIN_ARCH=arm64` and a separate output directory. `DARLING_LIBOBJC`
can select an SDK's genuine Objective-C link stub instead of the default runtime
dylib. The local source SDK has incomplete arm headers; do not disguise x86_64
bytes as an arm64 slice.

`tests/darwin_split.swift` is a consumer regression for shared libc errno,
UNIX2003 and capability error codes, Float80 math, stdio and Duration conversions.
Compile with the canonical source module, disable its direct Darwin autolink,
then link through the split reexports. This exercises the provider through the
missing install-name chain without needing the Linux compiler to import Apple's
newer SDK Swift interfaces. Keep runtime facade modules off the import path.

```sh
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c overlays/tests/darwin_split.swift \
  -target x86_64-apple-macosx26.0 -sdk "$DARLING_SDK" \
  -resource-dir "$SWIFT_RESOURCE_DIR" -I "$OVERLAY_BUILD_DIR/modules" \
  -I "$SWIFT_RESOURCE_DIR/shims" -disable-autolink-library swiftDarwin \
  -O -o "$OVERLAY_BUILD_DIR/darwin_split.o"
"$DARLING_LD" -arch x86_64 -platform_version macos 26.0 26.0 \
  -syslibroot "$DARLING_ROOT" -L "$SWIFT_RESOURCE_DIR/macosx" \
  -L "$OVERLAY_BUILD_DIR" "$OVERLAY_BUILD_DIR/darwin_split.o" \
  "$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" -lswiftCore \
  -lswift_errno -lswift_math -lswift_stdio -lswift_time \
  -lswiftsys_time -lswift_signal -lswiftunistd \
  -o "$OVERLAY_BUILD_DIR/darwin_split"
```

Run that executable only under a separate normally built/installed image.
Compilation and export coverage alone do not establish runtime behavior.

The optimized native fixture also exercises libsystem_m's combined sine/cosine
entrypoints: Clang can lower a scalar sine/cosine pair to `__sincos_stret` (or
`__sincosf_stret`). Their implementations must retain scalar libm backend calls,
not recursively optimize those calls into the combined entrypoint itself.
`src/libm/Source/sincos.c` applies function-local `no_builtin` contracts for just
those scalar operations; this leaves the exported aggregate-return ABI and
the caller's normal math optimizations unchanged.

The base-10 exponential entrypoints have the same constraint: `__exp10` and
`__exp10f` call the genuine `pow`/`powf` backends with base 10. Their
function-local `no_builtin` contracts prevent Darwin's optimizer from folding
those calls back into the entrypoints themselves and emitting an unreachable
trap. The scalar double/float ABI and backend special-value behavior are retained.

| Overlay | Sources | Notes |
|---|---|---|
| `libswiftDarwin` | `swiftlang/swift` `release/6.1`, `stdlib/public/Platform` (`Darwin.swift` and `tgmath.swift` pre-expanded with gyb) | Needed at build time by the other overlays: the Clang importer maps C `Boolean` to `Darwin.DarwinBoolean` |
| `libswiftObjectiveC` | `release/5.4`, `stdlib/public/Darwin/ObjectiveC` | Unmodified |
| `libswiftCoreFoundation` | `release/5.4` `CoreFoundation.swift`, plus `CGFloat.swift` from the 5.4 CoreGraphics overlay | Newer SDKs moved `CGFloat` into this overlay; it's declared `@_originallyDefinedIn(module: "CoreGraphics", ...)` so its symbols keep their `CoreGraphics` mangling |
| `libswiftDispatch` | `release/5.4`, `stdlib/public/Darwin/Dispatch` | `Scheduler.swift` carries the Combine `Scheduler` conformance of `DispatchQueue` back (the 5.4 `Schedulers+DispatchQueue.swift`, which the build drops because it needs Combine; see "Combine" below and DARLING-CHANGES.md for the two-pass build that lands it). `Darling+NewerSDK.swift` and a designated `DispatchWorkItem.init(flags:block:)` add APIs from newer SDKs. `DarlingSerialExecutor.m` defines `OS_dispatch_queue_serial_executor` until Darling's libdispatch does |
| `libswiftos` | Clean-room (`os/os.swift`) | `Logger`, `os_log`, `os_signpost`, `OSSignpostID`, `OSSignposter`, `OSSignpostIntervalState`, `OSAllocatedUnfairLock`, and the `OSLog`/`OSLogType`/`OSSignpostType` extensions. `os_log` encodes arguments into the os_log buffer format and calls `_os_log_impl`. Signposts report as disabled: Darling's libsystem_trace signpost entry points abort |
| `libswiftXPC` | Clean-room (`XPC/XPC.swift`) | `XPCSession`, `XPCDictionary` (copy-on-write, with Bool/String/integer/object/dictionary/array subscripts), `XPCArray` and `XPCRichError`, on top of libxpc's C API |
| `libswiftFoundation` | `release/5.4` `stdlib/public/Darwin/Foundation/{String,NSArray,NSDictionary,NSSet,NSError,NSNumber,NSRange,Foundation,NSStringAPI,UUID,Notification,IndexPath,Date,ReferenceConvertible,URL,Data,DataProtocol,ContiguousBytes,Pointers+DataProtocol,Collections+DataProtocol,IndexSet,NSObject,CharacterSet,Locale,TimeZone,DateInterval,DateComponents,Calendar,JSONEncoder,PlistEncoder,Codable,PersonNameComponents,Boxing,NSFastEnumeration,NSPredicate,FileManager,NSCoder,AffineTransform,Publishers+KeyValueObserving,Publishers+Locking}.swift`, reduced (`CocoaError.swift`, `NSDictionary+Literal.swift`, `NSString+Literal.swift` and `URLResourceValues.swift` hold the parts taken from `NSError.swift`, `NSDictionary.swift`, `NSString.swift` and `URL.swift`); `Decimal.swift` from the later Darwin overlay in swift-corelibs-foundation (the 5.4 copy traps in `init?(exactly:)`), without its unused shims import; `URLComponents.swift`, `JSONSerialization+Swift.swift`, `LocalizedStringResource.swift` and `NotificationCenter+Async.swift` clean-room | **Intentionally partial:** `CharacterSet` (the `url*Allowed` sets are built from their RFC 3986 character classes, as Darling has no `_CFURLComponentsGetURL*AllowedCharacterSet`); `URLComponents` and `URLQueryItem` are written from the API documentation and RFC 3986 as pure Swift values, because Darling's `NSURLComponents` only implements `scheme`, `host` and `URL` (no bridging to `NSURLComponents`/`NSURLQueryItem`); key-value observing (`observe(_:options:changeHandler:)`, `NSKeyValueObservation`, `NSKeyValueObservedChange`, KeyPath-based `willChangeValue`/`didChangeValue`, and the Combine `publisher(for:options:)`/`NSObject.KeyValueObservingPublisher`, which makes this overlay import `Combine.framework` as Apple's does), without the swizzle that backs `NSKeyValueObservingCustomization`; the value types `IndexSet` (the `__NSIndexSetRange*` shims are implemented in Swift over `-enumerateRangesUsingBlock:`), `UUID`, `Notification`, `IndexPath`, `Date` (plus `Date.now`, `advanced(by:)` and `distance(to:)` from newer SDKs), `URL` (without bookmarks, which Darling's NSURL doesn't implement, and with `creationDate`, file type flags and `fileSize` in `URLResourceValues`/`resourceValues(forKeys:)`, but with `URL.DirectoryHint` and `appending(path:directoryHint:)` from newer SDKs), and `Data` with `DataProtocol`/`ContiguousBytes`. `Data` keeps the 5.4 overlay's `@frozen` layout (`_Representation`, `InlineData`, `InlineSlice`, `LargeSlice`, `__DataStorage`), whose internals apps inline. Deallocators use `free`/`munmap`/`vm_deallocate` directly instead of Foundation SPI; the `_ObjectiveCBridgeable` conformances of `String`, `Array`, `Dictionary`, `Set`, the integer types, `Float`, `Double`, `CGFloat` and `Bool`; `NSNumber` literals; `Error` ↔ `NSError` bridging (`_convertErrorToNSError`, `LocalizedError`, `CustomNSError`, `_BridgedStoredNSError`, and the hooks the runtime looks up by name); `String(format:)`, `NSLocalizedString`, `NSLog`, `NSNotFound`, `Range(NSRange, in:)`; and the `CVarArg` and `AnyHashable` conformances of bridged types. Non-verbatim `Dictionary` bridging always uses the 5.4 overlay's enumeration path, so it doesn't need the `__NSDictionaryGetObjects` shim. `NSString` literals and `appendingFormat`; `NSCoder.decodeObject(of:forKey:)` for a class and for an array of classes; `CocoaError` with only `fileWriteFileExists` among its codes; `NSFastEnumerationIterator` with `for`-`in` over `NSArray` and `NSEnumerator`; `NSDictionary` literals; `NSPredicate(format:_:)`; and `FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)` over `-enumeratorAtURL:…`, which needs `NSURLResourceKey` imported as `URLResourceKey` (the SDK's `Foundation.apinotes`). The other error code tables (`URLError`, …) and Darling-unsupported pieces (user-info value providers, recovery attempters) are left out. The arm64 slice replaces none of the x86_64 slice's API. It also builds `AttributedString` and the `FormatStyle`/`ParseableFormatStyle`/`ParseStrategy`/`DiscreteFormatStyle` protocols from [apple/swift-foundation](https://github.com/apple/swift-foundation), which `build.sh` fetches at the pinned commit `dbacc67` (tag `swift-6.3.3-RELEASE`) rather than vendoring: 34 of its 37 files are byte-identical to upstream and are compiled straight out of the checkout, and only the three Darling cannot build as they stand live in `Foundation/`. `AttributedString`'s BigString storage comes the same way from [apple/swift-collections](https://github.com/apple/swift-collections) at `c11818f3` (tag `1.1.6`), compiled without library evolution straight into the dylib. Set `SWIFT_FOUNDATION_SRC` or `SWIFT_COLLECTIONS_SRC` to an existing checkout of the matching commit to build offline; neither checkout is written to. The `#if FOUNDATION_FRAMEWORK`-guarded half of those files (the attribute scope's dynamic registration, the `Codable` conformances, `AttributedString(NSAttributedString)`), the ICU-backed format styles and `AttributedString(localized:)`, and `AttributedString(markdown:)` are left out rather than approximated; see `DARLING-CHANGES.md` The `Locale.Language`, `Locale.LanguageCode`, `Locale.Region` and `Locale.Currency` value types come from swift-foundation's `FoundationEssentials`, which needs no ICU; `Locale.Components` is excluded because its `icuIdentifier` needs swift-foundation's `Calendar` and `TimeZone` internals, and `Locale.language`, `Locale.region`, `Locale.currency` and `Locale.Language.languageCode` are read from `NSLocale` instead of ICU (see `DARLING-CHANGES.md`). |
| `libswiftCoreGraphics` | Written for Darling (`CoreGraphics/CoreGraphics.swift`), plus `CGContext.addLine(to:)` and `addArc(center:radius:startAngle:endAngle:clockwise:)` from `release/5.2` `stdlib/public/Darwin/CoreGraphics/CoreGraphics.swift` | `@_exported import CoreFoundation`: Darling's CoreGraphics has no Clang module, and `CGFloat` lives in the CoreFoundation overlay. The module lets the Clang importer map C `CGFloat` to `CoreGraphics.CGFloat`, and gives arm64 binaries that autolink `libswiftCoreGraphics` a slice. **Intentionally minimal:** only the two `CGContext` methods apps import. Darling's CoreGraphics headers include Foundation, so `CoreGraphics/shims` declares `CGContextRef` as a CF type (mangled `So12CGContextRefa`, as apps expect) and the two C functions. Apps bind these symbols to `CoreGraphics.framework`, which has to re-export `libswiftCoreGraphics` |
| `libswiftAppKit` | Clean-room (`AppKit/AppKit.swift`) | **Intentionally minimal:** `CGRect.fill(using:)`, `CGRect.frame(withWidth:using:)`, `NSSound.beep()` and `NSImage(imageLiteralResourceName:)`, on top of AppKit's `NSRectFillUsingOperation`, `NSFrameRectWithWidthUsingOperation`, `NSBeep` and `+[NSImage imageNamed:]`. Darling's AppKit has no Clang module, so `AppKit/shims` declares just those. `NSCompositingOperation` is a named enum there, because an anonymous `typedef enum` would mangle as a typealias instead of `So22NSCompositingOperationV` |
| `libswiftSceneKit` | Clean-room (`SceneKit/SceneKit.swift`) | **Intentionally partial:** the `SCNVector3`/`SCNVector4` conversions to and from `CGFloat`, `Float`, `Double`, `Int` and the `SIMD3`/`SIMD4` types, `CATransform3D` to and from `simd_float4x4`/`simd_double4x4`, and `SCNBoundingVolume`'s `boundingBox` and `boundingSphere`. Darling's SceneKit headers are a dump of the framework's internal classes and declare neither `SCNVector3` nor the `SCNBoundingVolume` methods, and the SDK ships no QuartzCore or simd module, so `SceneKit/shims` declares those. Tag naming decides the mangling: `SCNVector3` and `CATransform3D` are named tags and mangle `So10SCNVector3V`, while the simd matrices are typedefs of anonymous structs and mangle as typealiases, `So13simd_float4x4a`. Left out are the `_ObjectiveCBridgeable` conformances of `SCNVector3`/`SCNVector4` (Darling's Foundation has no `+[NSValue valueWithSCNVector3:]`), the `SCNGeometrySource`/`SCNGeometryElement` initializers and `SCNSceneSource.entryWithIdentifier(_:withClass:)`: Darling's SceneKit is a set of class stubs whose whole Objective-C method-name section is 86 bytes, so there is nothing for those to call |
Sources from the Swift project are licensed under the Apache License v2.0 with Runtime Library Exception. `AppKit/`, `CoreGraphics/` (except the two `CGContext` methods from 5.2), `os/`, `XPC/`, `SceneKit/`, `Dispatch/Darling+NewerSDK.swift`, `Dispatch/DarlingSerialExecutor.m`, `Dispatch/include/swift/Runtime/Debug.h` and `tests/` were written for Darling.
| `libswiftQuartzCore` | Clean-room (`QuartzCore/QuartzCore.swift`) | **Intentionally minimal:** `CAFrameRateRange.init(minimum:maximum:preferred:)`, the one QuartzCore Swift symbol apps import that the vendored 5.2.2 slice predates (`CAFrameRateRange` is macOS 12). Darling's QuartzCore has no Clang module and its headers predate the type, so `QuartzCore/shims` declares the three-float struct from `CABase.h`. `nil` for `preferred` is `0`, as in `CAFrameRateRangeMake`. The x86_64 slice's `CATransform3D` ↔ `NSValue` bridging is not reproduced here |
| `libswiftUniformTypeIdentifiers` | Clean-room (`UniformTypeIdentifiers/UniformTypeIdentifiers.swift`), written from the public `UniformTypeIdentifiers.swiftinterface` declarations | `UTType` wraps Darling's Objective-C `UTType` (darling `src/frameworks/UniformTypeIdentifiers`), which holds the type table, conformances and tag lookups; the 131 static types it exports, the initializers, `identifier`/`tags`/`supertypes`/`conforms(to:)` and the other properties, `Hashable`, `Codable` and `ReferenceConvertible` bridging. `UniformTypeIdentifiers/shims` declares the class (renamed `UTTypeReference` for Swift, as in Apple's SDK) and its constants, since the SDK has no Clang module for the framework. arm64 only; replaces the placeholder `libswiftUniformTypeIdentifiers.S`. **This payload also carries an x86_64 slice**, built here by `UniformTypeIdentifiers/build.sh` (see "UniformTypeIdentifiers" below). **Not included:** the `String` and `NSItemProvider` extensions, three of the four `URL` members, macOS 26's `referenceAccessoryURL` and `setDefaultHandler(to:completionHandler:)`, and `css`, `heics`, `exr`, `dng`, `jpegxl`, `tarArchive`, `ahap`, `geoJSON` and `linkPresentationMetadata`, whose Objective-C constants Darling does not export yet |
| `libswiftCoreText` | Clean-room (`CoreText/CoreText.swift`), written from Apple's public documentation of `AttributedString.AdaptiveImageGlyph` | **Intentionally partial:** `AttributedString.AdaptiveImageGlyph` (image content, equality, hashing, `Codable`) and the `CTAdaptiveImageGlyph._adaptiveImageGlyph(convertingFrom:)` conversion OpenSwiftUI binds by its mangled name, with package access so it stays out of clients' name lookup and clients need no shim module map. Apple does not document where the image content keeps the identifier and description, so `contentIdentifier`, `contentDescription` and `contentType` trap (VibeDarling/darling#845). `Codable` writes the image content as a single `Data` value, Darling's own form rather than Apple's. `CoreText/shims` declares Darling CoreText's private `CTAdaptiveImageGlyph` class. Left out: `init(_:)` from `NSAdaptiveImageGlyph`, which belongs in the AppKit overlay. arm64-only |
Sources from the Swift project are licensed under the Apache License v2.0 with Runtime Library Exception. `AppKit/`, `CoreGraphics/` (except the two `CGContext` methods from 5.2), `QuartzCore/`, `os/`, `XPC/`, `Dispatch/Darling+NewerSDK.swift`, `Dispatch/DarlingSerialExecutor.m`, `Dispatch/include/swift/Runtime/Debug.h` and `tests/` were written for Darling.
| `Combine.framework` | [cristim/OpenCombine](https://github.com/cristim/OpenCombine) (MIT), `Sources/OpenCombine`, fetched at pinned commit `10df981` with functional Merge publishers, plus the three patches in `Combine/patches/` | Not an overlay dylib but the framework binary itself, because Apple's Combine is pure Swift. Built as `-module-name Combine`, which is what makes the mangled names match. arm64 only (no x86_64 slice exists to merge with). **Intentionally partial:** see "Combine" below |
| `GroupActivities.framework` | Clean-room (`GroupActivities/Sources/GroupActivities.swift`) | Not an overlay dylib but the framework binary itself, because Apple's GroupActivities is pure Swift and has no open-source twin. Built as `-module-name GroupActivities`, which is what makes the mangled names match. arm64 only. **Deliberately inert:** see "GroupActivities" below |

The OpenCombine sources `build.sh` fetches are MIT (Copyright (c) 2019 Sergej Jaskiewicz); `Combine/LICENSE` is kept in the tree because the `Combine.framework` binary committed here is built from them. `Combine/helpers.c` and the patches in `Combine/patches/` were written for Darling. Sources from the Swift project are licensed under the Apache License v2.0 with Runtime Library Exception. `AppKit/`, `CoreGraphics/` (except the two `CGContext` methods from 5.2), `CoreText/`, `GroupActivities/`, `os/`, `XPC/`, `Dispatch/Darling+NewerSDK.swift`, `Dispatch/DarlingSerialExecutor.m`, `Dispatch/include/swift/Runtime/Debug.h` and `tests/` were written for Darling.

### Combine

Apple's Combine is pure Swift: every symbol apps bind from it is Swift-mangled (protocol
descriptors, nominal type descriptors, witness tables, dispatch thunks). There is no C or
Objective-C surface, so a stub framework exporting nothing cannot satisfy a client that binds
symbols from it, and a hand-written stub would have to reproduce generic metadata by hand.

Swift mangles the module name into every symbol, so building OpenCombine as `-module-name Combine`
with `-enable-library-evolution` produces the names apps actually import. This is a real
implementation, not a stub: `@Published` and `objectWillChange` are on live code paths, and
OpenCombine implements them rather than no-opping.

**Coverage.** The earlier 29-app scan found 261 unique Combine imports, 234 exported by
the initial framework build. This branch adds functional `Merge` and `MergeMany` from
`cristim/OpenCombine` commit `10df981`. A fresh scan on 2026-09-23 against the installed
FindMy and VoiceMemos binaries, using the same disposable Darling prefix before and
after replacing only Combine, resolved all three Merge imports in each app. FindMy's
three `Result.Publisher` imports are supplied since 2026-10-13, when `Result.Publisher`
became a real nested type of `Result` (patch 0004 below); that scan has not been re-run.
VoiceMemos has no remaining direct Combine imports. These are direct binding results, not
proof those apps launch or work.

The following APIs remain unimplemented in this framework build; counts and app names
are from the earlier scan and should be rechecked against current binaries:

| Missing | Symbols | Apps affected |
|---|---|---|
| `Publishers.CombineLatest`, `CombineLatest3`, `CombineLatest4` and the four `combineLatest` overloads | 13 | Freeform, Podcasts, FindMy, Reminders, Font Book, Journal, Shortcuts |
| `Publishers.CollectByTime`, `TimeGroupingStrategy` and `collect(_:options:)` | 7 | Font Book, VoiceMemos |

Adding them is source work in this directory, not a structural problem. `Result.Publisher` used to be
the third row; it is implemented (patch 0004), and the reason the table gave for it is the reason it
had to be a structural change rather than a typealias: a typealias gets no nominal type descriptor of
its own, so the three imports an app makes for the nested type cannot be satisfied by one.

**Runtime.** `tests/combine.swift` runs the framework under Darling and passes 15/15: `Just`
delivering a value and finishing, `PassthroughSubject` forwarding, `CurrentValueSubject` replaying
its current value, a `filter`/`map` chain, `AnyCancellable.cancel` stopping delivery, `Fail`
arriving as a failure completion, and the `ObservableObject`/`@Published` path, where
`objectWillChange` fires once per mutation through the `_enclosingInstance` subscript.
The three new checks exercise Merge waiting for both upstream completions, interleaved
delivery, and MergeMany forwarding three upstreams. The `@Published` group confirms
`Mirror`-based field discovery works on Darling's Swift runtime.

**Still not verified.** Apple's Combine ABI is not available to diff against (no Xcode or CLT SDK
here, and the binary lives in the dyld shared cache), so the requirement sets of the resilient
protocols and the layout of any `@frozen` types are checked by reasoning about the imported
symbols, not by a full export diff. The runtime test covers the behaviour listed above, not all of
Combine: schedulers, backpressure and the operator graph beyond `filter`/`map` are unexercised.
`ObservableObject` finds `@Published` fields with `Mirror` where Apple walks type metadata, which
is correct but slower. Thread-safety and demand semantics follow OpenCombine's test suite, not
Apple's.

**`canImport(Combine)` is true while compiling the module named `Combine`.** OpenCombine guards
some declarations on `#if !canImport(Combine)`, expecting to be a fallback next to Apple's Combine;
under `-module-name Combine` those blocks are always excluded. That used to bound two of them,
`Result.Publisher`/`Result.publisher` and `Optional.Publisher`/`Optional.publisher`. Patch 0004
deletes the `Result` one: `Result.Publisher` is now declared directly, so its
`typealias Publisher = OCombine.Publisher` no longer names anything. `Optional`'s block is still
excluded, and the substantive extensions in both files sit after the `#endif` and do compile, so
nothing else is lost. Measured, not assumed: `r.publisher` still fails to typecheck against the built
module while `r.ocombine.publisher` succeeds -- patch 0004 adds the TYPE only, not Apple's
`Result.publisher` property, because no image in the ladder's load closure demands the property.

What a block like that adds is a typealias, and a typealias does not get its own nominal type
descriptor, so un-guarding it could not supply the three `Result.Publisher` imports. The fix is to
move the struct out of the `OCombine` namespace, which is what patch 0004 does: `Publisher` becomes a
real nested type of `Result`, the nesting Apple's ABI uses and the one
`XCSourceControl.framework`'s imports name
(`_$ss6ResultO7CombineE9PublisherVMa`/`VMn`/`Vyxq__GAcdCMc`). The trap is worth knowing before
editing these files: it is silent, and on a project where more declarations are guarded this way it
can collapse a whole module.

**Fetched, not vendored.** 92 of OpenCombine's 103 `Sources/OpenCombine` files, plus
`COpenCombineHelpers.h` and its module map, are used exactly as upstream ships them, so `build.sh`
fetches the package at the pinned commit `1c6f02c` instead of keeping 18,000 unmodified lines in
this repository. Set `OPENCOMBINE_SRC` to an existing checkout of that commit to build offline.

The other 11 files need four changes, which live in `Combine/patches/` and are applied to
a copy of the checkout, never to the checkout itself:

| Patch | Files | What |
|---|---|---|
| `0001-qualify-nested-types-with-Combine.patch` | 7 | The module qualifier `OpenCombine.` becomes `Combine.`, where a nested type named `Publisher` would otherwise shadow the protocol |
| `0002-drop-inlinable-for-library-evolution.patch` | 5 | `@inlinable`, `@usableFromInline` and `@_fixed_layout` are removed: OpenCombine is not written for library evolution and the compile fails on them under `-enable-library-evolution` |
| `0003-import-helpers-implementation-only.patch` | 4 | `COpenCombineHelpers` is imported `@_implementationOnly`, so clients of `Combine`, and through the KVO publisher of `Foundation`, load it without the fetched checkout's module map; the exported symbol set is unchanged (1680 before and after) |
| `0004-nest-result-publisher-directly.patch` | 3 | `Result.Publisher` moves out of the `OCombine` namespace to be a real nested type of `Result`, and every `Result<...>.OCombine.Publisher` in the module follows it, so `Just.setFailureType(to:)` returns the type Apple's ABI names. 63 exported names change spelling and none is lost (1680 before and after, deployed) |

`AnySubscriber.swift` takes the first two. Patches 0001-0003 affect no mangled name: the framework
built that way exports the same 1662 symbols, as a set, as the vendored tree it replaces. Patch 0004
is the one that does change mangled names, on purpose and only in the `Result` family; it was
measured against the ladder's whole 254-image load closure before landing -- none of the 63 names it
retires is imported by any image, and the name it must add is imported by exactly one,
`XCSourceControl.framework`. The second patch is
not optional; dropping it and compiling the rest gives 48 errors, the first being `'let' property
'box' may not be initialized directly` in `AnyPublisher.swift`.

`helpers.c` replaces OpenCombine's `COpenCombineHelpers.cpp` with a C implementation of the same
header (the identifier counter, `os_unfair_lock`, and a recursive `pthread_mutex`), so the framework
needs no libc++. That header is the fetched one, so a future pin that changes it becomes a compile
error here rather than a silent divergence. The `.gyb` templates in the checkout are not compiled:
the `GENERATED-*.swift` files they produce are what `collect_sources` picks up, and a template still
carrying the old module name would regenerate the wrong one. OpenCombine's
`RemainingCombineInterface.swift` reproduces Apple's interface and is outside `Sources/OpenCombine`,
so it is never compiled either.

Landing this also unblocked `Schedulers+DispatchQueue.swift` in the Dispatch overlay, which was dropped
because it needs Combine. That landed as `Dispatch/Scheduler.swift`: build-arch.sh links the Dispatch
module a second time after the Combine block, with `-D DARLING_DISPATCH_COMBINE` and the Combine binary,
so the conformance and its `SchedulerOptions` bind from `libswiftDispatch.dylib` (see DARLING-CHANGES.md).

### Why Foundation is bridging-only

The full 5.4 Foundation overlay doesn't compile against Darling's Foundation headers, which have no `@property` declarations, nullability or Swift names; that gives about 2,300 errors. It also calls Objective-C APIs Darling lacks. macOS 14+ apps import their Swift Foundation symbols (1,616 of them in macOS 26's apps) from `Foundation.framework` itself, so a fuller overlay would also need Darling's Foundation to re-export it. Bridging `String` and the collection types is the piece Swift code needs first: 25 of the apps import the `Array`/`Dictionary`/`Set` bridging entry points. To be useful from Swift, it relies on `Foundation.apinotes` `SwiftBridge` entries (VibeDarling/darling-foundation#5).

### StringProtocol range replacement

`replacingCharacters(in:with:)` accepts generic replacement strings and range
expressions. It resolves bounds against the original receiver, so a `Substring`
with nonzero base indices is not rebased through a copied `String`. The native
slice-concatenation implementation follows the current SDK's public inlinable
body and reserves UTF-8 capacity for contiguous operands without an NSString
bridge. `tests/string_replacing_characters.swift` checks Unicode, sliced
receivers and replacements, closed/partial ranges, deletion and empty insertion
boundaries through the public API.

## Coverage of what macOS 26 apps import

Measured against every binary in `/System/Applications` of a macOS 26.6.2 install:

- **ObjectiveC:** 14/14 symbols.
- **CoreFoundation:** 15/15, including the `$s12CoreGraphics7CGFloatV…` metadata and conformances.
- **os:** 44/44.
- **XPC:** 21/21.
- **Dispatch:** the Combine `Scheduler` conformance of `DispatchQueue`, its `SchedulerTimeType` and `SchedulerOptions`, and the ten symbols apps bind through them are declared by `Dispatch/Scheduler.swift` (the 5.4 file the build had dropped), so the 10 missing names are covered; Combine is closed source, but this tree builds OpenCombine as module `Combine`, which is what the declarations were checked against.
- **Foundation:** 654 of the 1,288 unique Swift symbols apps bind to `Foundation.framework`. That fully covers TextEdit, Chess, Passwords, Clock, Stocks, Contacts, Games, Phone, Calendar, FaceTime, Home and News. Each remaining app also needs API from macOS 12+ Foundation that this overlay does not cover (`Predicate`, `LocalizedStringResource`, async notification sequences, and the ICU-backed half of `AttributedString` and `FormatStyle`). Apps bind these symbols to `Foundation.framework`, so they only resolve once Darling's Foundation re-exports this dylib (a CMake `-reexport_library`, tested by adding the load command to a copy of Foundation).
- **CoreGraphics:** the 2 `CGContext` methods Boot Camp Assistant binds to `CoreGraphics.framework`, out of 36 unique Swift symbols the latest app scan found missing there.
- **AttributedString and FormatStyle:** measured separately from the 1,288-symbol Foundation total above, which predates this overlay code. Of the 262 `$s10Foundation…` symbols in those two families that the app corpus imports, 64 are defined by other frameworks' extensions (SwiftUI, UIKit, Accessibility, AppKit, Speech, WeatherUI, JournalShared) and can only come from those frameworks. Of the remaining 198 that the Foundation overlay must define, it exports 94. The 104 still missing are 73 concrete ICU-backed format styles, 13 pieces behind `#if FOUNDATION_FRAMEWORK`, 7 markdown parsing, 3 `init(localized:)` and 8 closed localization option types. `AttributedSubstring` is complete (8/8) and `AttributeContainer` is 14/15.
- **AppKit:** 3 of the 110 unique Swift symbols apps bind to `AppKit.framework`, plus `NSImage(imageLiteralResourceName:)`, which Boot Camp Assistant binds. That fully covers TextEdit, Calculator and Boot Camp Assistant; Freeform and Reminders also use them. The rest is mostly `NSDiffableDataSourceSnapshot`/`NSCollectionViewDiffableDataSource` and a few property wrappers. AppKit.framework has to re-export `libswiftAppKit`, the same way Foundation re-exports `libswiftFoundation`. With both re-exports in place, TextEdit loads 241 libraries and stops only at TextKit 2 classes that Darling's AppKit doesn't implement yet.
- **QuartzCore:** the single Swift symbol AppZapper 3000 binds to `libswiftQuartzCore` on arm64 (`CAFrameRateRange.init(minimum:maximum:preferred:)`). Before this the dylib had no arm64 slice at all, so any arm64 binary with a non-weak `LC_LOAD_DYLIB` on it failed to load regardless of which symbols it used.

## Building

See the header of `build.sh` for the required toolchain, resource directory, and Darling SDK/ld64/libSystem paths. The Darling SDK must include the Clang module maps for Darwin, ObjectiveC, Dispatch, os, XPC, CoreFoundation and Foundation, and the `sys/cdefs.h` default-platform fix. Without that fix, arm64 code links against `$UNIX2003` symbol variants that don't exist. Foundation also needs the CoreServices sub-frameworks (`AE`, `CarbonCore`) reachable as top-level frameworks and the `libDER/DERItem.h` guard.

## Tests

`tests/os_xpc.swift` covers `Logger`, `os_log` with arguments, signpost IDs and intervals, `OSAllocatedUnfairLock` across threads, `XPCDictionary`/`XPCArray` and `XPCSession`. `tests/objc_only.swift` and `tests/objc_cf.swift` cover an NSObject subclass with `@objc` methods and selectors, NSObject `Equatable`/`Hashable`, `autoreleasepool`, `ObjCBool`, CF types as `Hashable` (`_CFObject`), CFString round trips, and CGFloat. `tests/string_bridging.swift` covers `String` ↔ `NSString` conversions, `String` arguments and results of Objective-C methods, `AnyObject` casts and small-string bridging. It passes 8/8 under Darling with darling-foundation#6 installed. Before that fix, `-[NSString uppercaseString]` on a Swift-native string returned garbage. `tests/collection_bridging.swift` covers `Array`, `Dictionary` and `Set` round trips through their NS counterparts: verbatim and non-verbatim element types, collections built in Objective-C, failing conditional casts, and `nil` → empty. It passes 15/15. `tests/errors_numbers.swift` covers `Error` → `NSError` (with `LocalizedError`/`CustomNSError`), `NSError` → `Error` including casts to a `_BridgedStoredNSError`, `catch let error as NSError`, `NSNumber` literals and bridging, `String(format:)`, `NSLocalizedString`, `NSNotFound` and `Range(NSRange, in:)`. It passes 24/24. `tests/uuid_notification.swift` (UUID generation, parsing, bridging, hashing and ordering; `Notification` bridging, equality and delivery through `NSNotificationCenter`) and `tests/indexpath_date.swift` (`IndexPath` literals, ordering and bridging for 0, 1, 2 and 3 indexes; `Date` arithmetic, comparison and `NSDate` bridging) pass under Darling. So does `tests/url.swift`: scheme/host/port/user/path/query/fragment, relative URLs, file URLs, path appending and deleting (including `appending(path:directoryHint:)`), `NSURL` bridging, equality and hashing. `tests/data.swift` covers inline and large representations, slices, `replaceSubrange`, equality and hashing, `NSData`/`NSMutableData` bridging (including copy-on-write of a bridged mutable data), Base64, `write(to:)`/`init(contentsOf:)` and `range(of:)`. `tests/indexset_kvo.swift` covers `IndexSet` insertion, ranges, `rangeView`, set algebra, `filteredIndexSet` and `NSIndexSet` bridging, plus `observe(_:options:)` on `@objc dynamic` properties with new and old values, several observations, `invalidate()`, and an optional property set to nil. `tests/url_components.swift` covers parsing (user info, IPv6 hosts, ports, relative references, invalid input), decoded and percent-encoded accessors, building URLs, `queryItems` encoding, the forbidden component combinations, `init(url:resolvingAgainstBaseURL:)` and value semantics. `tests/character_set.swift` covers the predefined sets, the URL allowed sets, building and set algebra, `NSCharacterSet` bridging and value semantics. `tests/locale.swift` covers identifiers and their components, `current`/`autoupdatingCurrent` (checked against `NSLocale`, since Darling's container can have no locale defaults), equality and hashing, the identifier lists, localized names and `NSLocale` bridging. `tests/string_api.swift` covers the `StringProtocol` NSString APIs apps use (trimming, splitting, replacing, searching and comparing, including ranges on substrings), `enumerateSubstrings` (compared with NSString), `String.Encoding` with `data(using:)`/`init(data:encoding:)`, percent encoding, `cString(using:)` and `write(to:atomically:encoding:)`. `tests/timezone.swift` covers identifiers, GMT offsets and daylight saving time across a New York winter and summer date, `init(secondsFromGMT:)`/`init(abbreviation:)`, `current`, the identifier and abbreviation lists, equality, hashing and `NSTimeZone` bridging. It checks `autoupdatingCurrent` only when TZ is set, because Darling's `+localTimeZone` crashes without it. `tests/numeric_bridging.swift` covers `NSNumber` bridging for `UInt8`, `Int16`, `UInt16`, `Int32`, `UInt32`, `UInt64`, `UInt`, `Float` and `CGFloat`: round trips, exactness checks on conditional casts, and elements of `NSArray` and `NSDictionary`. It passes 37/37. Darling's NSNumber stores unsigned 64-bit values above `Int64.max` as signed, so `NSNumber(-1) as? UInt` succeeds there (macOS returns nil) until Darling stores them as 128-bit CFNumbers; the test only checks the round trips. `tests/calendar.swift` covers Gregorian date composition and decomposition, adding components and differences, unit intervals, ranges and ordinality, the granularity comparisons, today/yesterday/tomorrow/weekend checks, date searches (`nextDate` forwards and backwards, leap days, quarters and weeks giving one date per instance, a repeated DST hour, a day without midnight, years that never match, `enumerateDates`, setting components), weekday symbols against `NSDateFormatter`, copy-on-write, equality, hashing and bridging for `Calendar` and `DateComponents` (including nanoseconds and `weekOfMonth`), `isValidDate`, `Locale.calendar` and `DateInterval`. It passes 82/82 with TZ unset and with `TZ=UTC`. `tests/json.swift` covers `JSONEncoder`/`JSONDecoder`: sorted keys (numeric, case-insensitive order), `withoutEscapingSlashes` and pretty printing including empty containers, floating-point output, round trips of a `Codable` struct, nulls, Unicode, `\u` escapes and surrogate pairs, a byte-order mark, top-level fragments, numbers at the integer limits (including `UInt64.max`), type-mismatch, overflow, invalid-JSON (lone surrogates, trailing garbage, leading zeros, invalid UTF-8) and missing-key errors, non-conforming floats, snake-case keys, ISO 8601, millisecond and custom date strategies. It passes 39/39. JSON input must be UTF-8; macOS also detects UTF-16 and UTF-32. `tests/plist.swift` covers `PropertyListEncoder`/`PropertyListDecoder`: binary and XML round trips of a `Codable` struct (strings needing escapes, dates, data, nested containers, `nil` in an unkeyed container as `$null`, `Int64.min` and `UInt64.max`), the XML written, decoding a hand-written XML property list and reporting its format, `superEncoder`/`superDecoder`, `userInfo`, rejecting top-level fragments when encoding, invalid data, fixed-width integer limits, overflow, fractional integers, `Bool`/number mismatches and missing keys. It passes 39/39. `tests/l10n_notifications.swift` covers `String(localized:)` with string, specifier and placeholder interpolations and a literal percent sign, `String(localized:defaultValue:)`, `LocalizedStringResource` literals, interpolations, keys and tables, interpolating a resource, lookups in a strings table written at run time (including a translation that reorders arguments and a bundle given by URL), `NSObject` as `CustomStringConvertible`, and `NotificationCenter.notifications(named:object:)` delivering matching notifications in order, including one posted from another thread. It passes 19/19. `tests/person_name_components.swift` covers `PersonNameComponents`: every component's getter and setter, the memberwise initializer and its defaults, `phoneticRepresentation` stored by value, copy-on-write, an optional-chained write to a nested component, bridging to and from `NSPersonNameComponents` (both directions copy, including `phoneticRepresentation`), `AnyObject` casts, equality (including components that differ only in `namePrefix`, only in `phoneticRepresentation`, or in nil against empty), hashing, `AnyHashable`, `description` and a `Codable` round trip. It passes 24/24 with darling-foundation#18 (`NSPersonNameComponents`) installed. `tests/bootcamp_foundation.swift` covers `for`-`in` over `NSArray` (more than one fast-enumeration buffer), `NSEnumerator` and `keyEnumerator()`, `NSDictionary` and `NSMutableDictionary` literals, `NSPredicate(format:)` with `%d` and `%@`, `catch CocoaError.fileWriteFileExists` and `as? CocoaError`, and `FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)` over a temporary directory tree. It passes 20/20. Darling's directory enumerator never calls the error handler, so that path isn't tested. `tests/console_foundation.swift` covers ASCII, non-ASCII, empty, single-scalar and `NSMutableString` literals, `appendingFormat`, both `NSCoder.decodeObject(of:forKey:)` variants on a keyed archive (right and wrong class, missing key, `nil` classes, a class list with secure coding on), and `URL.resourceValues(forKeys:)` (a recent `creationDate` for a new file, nil when not requested, throwing for a missing file). It passes 18 of 20 checks today. Both failures are Darling CoreFoundation bugs: file dates come back 31 years late (Unix seconds passed as `CFAbsoluteTime`), and a missing file doesn't make `-resourceValuesForKeys:error:` fail. Darling patches for both are written (`darling-corefoundation-nsurl-resource-dates` and `-resource-errors`). `tests/appkit_coregraphics.swift` covers `CGContext.addLine(to:)` and `addArc(center:...)` on a bitmap context's path (a quarter counterclockwise and three quarters clockwise, so the `clockwise` flag is checked) and `NSImage(imageLiteralResourceName:)` finding a named image. It passes 6/6. `tests/decimal.swift` covers `Decimal` (the macOS `NSDecimal`, renamed by darling-foundation's API notes, so its members mangle as `So9NSDecimala` extensions): literals, the four operators including 1/3, 2/3 and division by zero, `isZero` and the other `FloatingPoint`-style properties, comparison, hashing, rounding through `NSDecimalRound`, `description`, `Decimal(string:)`, `Codable` and `NSDecimalNumber` bridging, with expected values from Apple's overlay tests. It needs darling-foundation's exact `NSDecimal` arithmetic. `tests/scenekit.swift` covers the SceneKit overlay's conversions: `SCNVector3`/`SCNVector4` from `CGFloat`, `Float` and `Int`, the `SIMD3`/`SIMD4` conversions in both directions, and `CATransform3D` to and from `simd_float4x4` and `simd_double4x4` including the column-major element order. It passes 12/12 under Darling. It leaves out `SCNBoundingVolume`, whose methods Darling's SceneKit does not implement. Build the tests for `arm64-apple-macosx26.0` against these overlays, link with Darling's ld64 (`objc_only`/`objc_cf` also need `-Xfrontend -disable-objc-attr-requires-foundation-module`), and run them with `darling shell`. Tests that import `CoreGraphics` or `AppKit` need `-Xcc -fmodule-map-file=` for `CoreGraphics/shims/module.modulemap` and `AppKit/shims/module.modulemap`. `appkit_coregraphics` also needs `-import-objc-header tests/appkit_coregraphics.h` and links CoreGraphics and AppKit.

`tests/combine.swift` covers the Combine framework: `Just`, `PassthroughSubject`, `CurrentValueSubject`, a `filter`/`map` chain, `AnyCancellable.cancel`, `Fail`, `ObservableObject` with `@Published`, and functional `Merge`/`MergeMany`. It passes 15/15 under Darling. It imports only `Combine` and links the built `Combine.framework` binary.

`tests/kvo_publisher.swift` covers `publisher(for:options:)` on `@objc dynamic` properties: the default `[.initial, .new]` options delivering the current value and then each change, `[.new]` delivering only changes, `didChange()`, `cancel()` stopping delivery, a subscriber with a demand of one receiving only the cached initial value, and `NSObject.KeyValueObservingPublisher` equality. It passes 9/9 under Darling, and links `Combine.framework` as well as the overlays.

`tests/uniform_type_identifiers.swift` covers the UniformTypeIdentifiers overlay: `UTType.folder` and the other symbols AppZapper 3000 imports, static type identifiers, conformance, supertypes, identifier/filename-extension/MIME/tag lookups (including dynamic types), preferred tags, exported and imported types, hashing, bridging to and from the Objective-C `UTType`, and `Codable` for `UTType` and `UTTagClass`. It passes 46/46 under Darling. Build it like the tests above with `-Xcc -fmodule-map-file=` for `UniformTypeIdentifiers/shims/module.modulemap`, and link `libswiftUniformTypeIdentifiers.dylib` and `libswiftFoundation.dylib`.

`tests/coretext_adaptive_image_glyph.swift` covers the CoreText overlay: `AttributedString.AdaptiveImageGlyph` image content, equality, hashing, use in a `Set`, the `Codable` form with JSON and property-list round trips, and the conversion to `CTAdaptiveImageGlyph` called through the mangled name OpenSwiftUI binds. It passes 11/11 under Darling with darling-cocotron's `CTAdaptiveImageGlyph` installed. Run with `contentIdentifier`, `contentDescription` or `contentType` as its argument, it reads that member, which must trap with a message naming VibeDarling/darling#845. Build it with `-Xcc -fmodule-map-file=` for `CoreText/shims/module.modulemap` and `UniformTypeIdentifiers/shims/module.modulemap`, and link `libswiftCoreText.dylib`, `libswiftUniformTypeIdentifiers.dylib`, `libswiftFoundation.dylib` and CoreText.

## CryptoKit

`../CryptoKit.framework/Versions/A/CryptoKit` is [swift-crypto](https://github.com/apple/swift-crypto) (Apache-2.0) built as module `CryptoKit`, from the `darling/cryptokit-module` branch of the fork at [cristim/swift-crypto](https://github.com/cristim/swift-crypto), pinned in `build.sh` by commit rather than by branch so the build stays reproducible. The fork's `DARLING-CHANGES.md` is the authoritative list of how it diverges from upstream; the summary is:

- Every source file opens with `#if canImport(CryptoKit)` / `@_exported import CryptoKit`. `canImport(CryptoKit)` is **true when the module being compiled is itself named CryptoKit**, so building the package this way collapses it into an empty module that re-exports itself. The fork's guards also test `!DARLING_CRYPTOKIT_MODULE`, and `build.sh` passes `-D DARLING_CRYPTOKIT_MODULE`.
- Two sites qualify types as `Crypto.Digest` / `Crypto.MessageAuthenticationCode` to disambiguate from same-named associated types. There is no `Crypto` module under `-module-name CryptoKit`, so the fork names `CryptoKit.` instead.
- Darling cannot link BoringSSL into this framework, so the fork adds a pure-Swift SHA-256 (FIPS 180-4) supplying `DigestImpl`, replacing the BoringSSL-backed one.

**Scope.** SHA-256 and HMAC-SHA-256, plus `SymmetricKey`, `Digest`/`SHA256Digest`, `HashFunction`, `HashedAuthenticationCode` and `MessageAuthenticationCode`. That is what the corpus binds: the app that motivated this binds 13 CryptoKit symbols, all inside that surface. SHA-384/512, SHA-3, MD5/SHA-1, AES, ChaChaPoly, key agreement, signatures and HKDF are deliberately left out. Five macOS 26 apps (Weather, FindMy, Maps, Freeform, Music) also link CryptoKit; their per-symbol demand was not re-derived, because the macOS system volume was not mounted, so the boundary may need widening.

**Correctness.** The fork's `Darling/run-vectors.sh` builds the same subset natively for the host and runs published vectors: NIST FIPS 180-4 SHA-256 (empty, `"abc"`, the 448- and 896-bit messages, one million `'a'`), the same one-million-`'a'` digest recomputed in 1, 7, 63, 64, 65, 127 and 1000-byte chunks to exercise the block buffer across the 64-byte boundary, value semantics when a half-fed hash is copied, and RFC 4231 HMAC-SHA-256 cases 1, 2, 3, 4, 6 and 7. 21/21 pass. That evidence comes from a **native Linux build of the identical sources**, not from running under Darling.

## System

`../libswiftSystem.dylib` is [swift-system](https://github.com/apple/swift-system) (Apache-2.0 with the Runtime Library Exception) built as module `System` by `System/build.sh`, pinned by commit `0b301619` (tag 1.6.6) rather than by tag. `/usr/lib/swift/libswiftSystem.dylib` is a load-time dependency of the guest's Xcode 26.3 DVTInstrumentsFoundation, IDEDistribution, XCTHarness and AppThinning, and 22 symbols are bound from it in that load closure, all eagerly through `__DATA_CONST,__got`.

**Fidelity.** Apple ships a `.tbd` for this library in the same SDK, and it is the ABI this build is measured against: it lists 657 mangled symbols, of which the build exports 650 and exports nothing Apple does not. The seven it lacks, all demangled, are five `System.Mach.Port` members spelling `_context` as `Swift.UInt` (this target's `mach_port_context_t` is `UInt64`, and Apple's tbd carries both spellings under two `targets:` groups, so that file merges more than one build) and `System.MachPortRight`'s protocol requirements base descriptor, which an empty protocol does not emit. No client in the load closure demands any of them.

**The one non-obvious dependency.** swift-system's Darwin sources need the Swift *overlay* of the Clang module `Darwin` (`Darwin.errno`, `Darwin.open`, `Darwin.openat` — the C prototypes are variadic, which the clang importer imports as unavailable). Apple's own `Darwin.swiftmodule` in the SDK cannot be used here: this compiler refuses it outright ("this SDK is not supported by the compiler"), and it `import _DarwinFoundation1._math`, a submodule Darling's regenerated module maps name `Darwin.C_math`. `System/build.sh` therefore compiles the *module* of this repo's `Darwin/` overlay sources for the same target and uses only its `.swiftmodule`, so the three symbols the System object references resolve against the payload's own `libswiftDarwin.dylib`, which exports them.

## SwiftDemangle

`../libswiftDemangle.dylib` is the Swift project's demangler — [swiftlang/swift](https://github.com/swiftlang/swift) at tag `swift-6.2.4-RELEASE` (Apache-2.0 with the Runtime Library Exception), `lib/Demangling` plus `lib/SwiftDemangle` — built as C++ for `x86_64-apple-macosx26.0` by `SwiftDemangle/build.sh`, pinned by commit `ee343b46` rather than by tag. `/usr/lib/swift/libswiftDemangle.dylib` is a load-time dependency of the guest's Xcode 26.3 XCTHarness, the **only** referrer of this install name inside `libxcodebuildLoader`'s load closure, and a NON-weak one: it binds three plain C entry points eagerly through `__DATA_CONST,__got` — `swift_demangle_getDemangledName`, `swift_demangle_getModuleName` and `swift_demangle_getSimplifiedDemangledName`. A real implementation is required rather than a shim: demangling is the whole API, so a placeholder would answer every call wrongly. (The CommandLineTools 15.3 copy of this library would NOT do: measured, 111 exports, and no `swift_demangle_getModuleName` at all.)

**Fidelity.** Apple ships a `.tbd` for this library in the same SDK (`MacOSX.sdk/usr/lib/swift/libswiftDemangle.tbd`), and it is the ABI this build is measured against: it names 235 symbols for `x86_64-macos` (237 across its three target groups). This build's export trie carries **all 235** and exports **nothing** Apple's file does not — zero in both directions. The toolchain's own copy of the library (`XcodeDefault.xctoolchain/usr/lib/libswiftDemangle.dylib`) exports the same 235, so the tbd and the shipped binary agree and this build reproduces both.

**The one source Apple's shipped library does not contain.** `lib/Demangling/CMakeLists.txt` lists `OldRemangler.cpp`, and Apple's library does not carry it. That is measured, not inferred: the file defines four non-assert string literals nothing else defines (`<curry-thunk>`, `<autodiff-function>`, `<method-descriptor>`, `<reabstraction-thunk>`), and all four are absent from Apple's shipped binary while present in a build that includes the file — and the three symbols only that file defines (`mangleNodeOld` ×2 and `mangleNodeAsObjcCString`) are absent from both Apple's tbd and its binary. Compiling it exports 238 symbols, three of them outside Apple's ABI and demanded by nothing in the load closure, so `build.sh` compiles the source set Apple ships. Old *de*mangling is not dropped: `OldDemangler.cpp` is compiled and `SWIFT_SUPPORT_OLD_MANGLING=1` is set, which is what the `_Tt` names still present in ObjC metadata need.

**Flags, all justified by measurement rather than guessed.** `-DNDEBUG`, `-fno-exceptions`, `-fno-rtti`: Apple's binary carries no assert-expression strings, no `__gcc_except_table` section and no typeinfo/vtable references. `-O2`, `-DSWIFT_SUPPORT_OLD_MANGLING=1`, `-DSWIFT_STDLIB_HAS_TYPE_PRINTING=1` and `-DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=1` are `lib/Demangling/CMakeLists.txt`'s own flags. The demangler needs LLVM *headers* but no LLVM library — it imports zero `llvm::` symbols, as Apple's copy does (which links `libobjc`, `libc++` and `libSystem` only). Darling's SDK ships no libc++ headers, so `LIBCXX_INCLUDE` must be pointed at a libc++ whose ABI matches the guest's (in this environment the Xcode SDK's `usr/include/c++/v1`). One load-command difference from Apple, named rather than hidden: the link records `/usr/lib/libc++abi.dylib` as a direct dependency because the tree's `libc++.1.dylib` re-export alone does not satisfy ld64 for `operator new`/`operator delete`; Apple's copy folds that into `libc++.1.dylib`. **Reproducible bytes.** The demangler's always-on assertion macro embeds `__FILE__`, which would otherwise make the artifact depend on the directory it was built in (a committed payload whose sha changes per builder, and a deploy receipt that cannot be verified); `build.sh` therefore passes `-ffile-prefix-map="$src"=` so the checkout's single absolute build path in the image normalises to `/lib/Demangling/Demangler.cpp`. Measured, not assumed: the same recipe built from two different checkout directories yields the identical sha256.

## UniformTypeIdentifiers

`../libswiftUniformTypeIdentifiers.dylib` is this repo's own clean-room UniformTypeIdentifiers overlay, compiled by `UniformTypeIdentifiers/build.sh` as module `UniformTypeIdentifiers` for `x86_64-apple-macosx26.0` with library evolution. It is the Swift half of the library: `UTType` wraps Darling's Objective-C `UTType` (`src/frameworks/UniformTypeIdentifiers`), which holds the type table, the conformances and the tag lookups, and every member here is a forward to it.

**The rung it answers.** `/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib` is the load-time dependency the ladder stops at after `libswiftDemangle`: the guest's Xcode 26.3 `XCTHarness.framework/Versions/A/XCTHarness` links it NON-weakly (`LC_LOAD_DYLIB`, compatibility version 1.0.0, current version 877.2.1), and it is the only libswift* still missing strongly from that framework's load commands — CoreImage, IOKit, Metal, OSLog, QuartzCore and simd are all `LC_LOAD_WEAK_DYLIB` and are correctly skipped. Measured per dependency field (never by substring) over the x86_64 slice with `llvm-nm -m`, XCTHarness binds TEN names from the field `libswiftUniformTypeIdentifiers`: nine strong plus the weak `__swift_FORCE_LOAD_$_swiftUniformTypeIdentifiers`. Three of the nine are macOS 26 API this overlay did not declare: `UTHardwareColor`'s type metadata accessor and nominal type descriptor, and `UTType.init(_deviceModelCode:enclosureColor:)`. The other six are `UTType`'s metadata accessor and nominal descriptor, `identifier` and `localizedDescription`, and the static `text` and `utf8PlainText`.

**Why this is a build and not the slice this repo commits.** The payload's committed `libswiftUniformTypeIdentifiers.dylib` (VibeDarling/darling-swift, git-lfs) is arm64-only, and its export trie carries 345 names — exactly the three macOS 26 names above are absent from it, so it was built from an earlier revision of this source than the one in the tree. It cannot serve an x86_64 guest either way; the slice beside it is built here, from this tree's source, and nothing was copied out of that checkout.

**What the macOS 26 API does here.** `UTHardwareColor` is plain data and is implemented in full — cases `rgb(UInt8,UInt8,UInt8)` and `indexed(Int32)`, with the compiler's synthesis for `Equatable`, `Hashable` and `Codable`, which is what Apple's `.tbd` names. `currentEnclosureColor` is `nil` and the device-model-code initializer returns `nil`, and those are this platform's answers rather than placeholders: Darling's Objective-C UniformTypeIdentifiers carries Apple's private backing entry points as stubs that report absence (`_UTHardwareColorGetCurrentEnclosureColor` and its four siblings return NULL) and has no device-model-code tag class at all (`_UTTagClassDeviceModelCode` is NULL), and this guest runs on no Apple hardware to ask.

**Fidelity.** Apple ships a `.tbd` for this library in the same SDK (`MacOSX.sdk/usr/lib/swift/libswiftUniformTypeIdentifiers.tbd`, install name `/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib`, current version 877.2.4, swift-abi-version 7), and it is the ABI this build is measured against: 628 symbols for `x86_64-macos`. This build exports **366** of them and exports **nothing** Apple's file does not — zero in the mine-only direction. The 262 it does not export are 143 members plus their 119 `vpZMV`/`vpMV` property descriptors, and the members are the boundary this overlay states: 123 are Apple's underscored SPI (`_macBookPro`/`_iOSDevice`/`_appleWatch`/`_iOSSimulator`, `_hfsCode(s)`, `_identifier(allowUndeclared:)`, `_exportedAs(from:)`/`_importedAs(from:)`, `_enclosureColor`/`_enclosureColors`, `_kindString`, `_childTypes`/`_parentTypes`, `_isCore`, `_isExported`/`_isImported`/`_isWildcard`, the `_appCategory*` family, the `_pasteboardType`/`_deviceModelCode` tag classes, `_ofItemAt`/`_forPromiseFileAt`), nine are the static types whose Objective-C constants Darling does not export yet (`css`, `heics`, `exr`, `dng`, `jpegxl`, `tarArchive`, `ahap`, `geoJSON`, `linkPresentationMetadata`), three are the remaining `URL` members (`appendingPathComponent(_:conformingTo:)`, `appendPathComponent(_:conformingTo:)`, `appendPathExtension(for:)`), six are the `NSItemProvider` extension, and two are macOS 26's `setDefaultHandler(to:completionHandler:)` and `referenceAccessoryURL`. `URL.appendingPathExtension(for:)` is implemented *because it is demanded* — the guest's `XCResultKit` binds it non-weakly from this dylib, and without it that image cannot load. Module flags are Apple's own, read off the SDK interface's `swift-module-flags` line (`-enable-library-evolution -library-level api -autolink-force-load -swift-version 5 -user-module-version 877.2.4 …`).

**One Foundation gap the overlay works around.** Darling's SDK declares `NSURLContentTypeKey` (`src/external/foundation/include/Foundation/NSURL.h`) and the Foundation re-export list carries it, but no image in the guest defines it — measured with `llvm-nm` over the deployed Foundation, the freshly built one and CoreFoundation. Naming the constant would therefore make this dylib depend at load time on a symbol nothing provides, so `URLResourceValues.contentType` builds the key from its raw value instead, which is the convention every sibling key in this tree follows (`src/external/corefoundation/NSURL.m` defines `NSString *const NSURLNameKey = @"NSURLNameKey";`, and swift-corelibs-foundation constructs it the same way: `URLResourceKey(rawValue: "NSURLNameKey")`). The missing definition belongs in CoreFoundation, next to those keys.

**Reproducible.** The recipe was built from two different checkout directories and the two dylibs are byte-identical (sha256 `a03252bc7c54a03081d81cf4bed317eb99d901f187880be072027ee95e22df4a`); no build path lands in the image, so no `-ffile-prefix-map` is needed. Its two inputs beyond the compiler and the tree are the payload's own `libswift*.dylib` (they are what it links, `SWIFT_PAYLOAD_LIBS`) and a `Foundation.swiftmodule` for the same target (`SWIFT_FOUNDATION_MODULES`: the overlay modules directory `overlays/build-arch.sh` produces with `SWIFT_DARWIN_ARCH=x86_64`), both named in the recipe's header.

## GroupActivities

`../GroupActivities.framework/Versions/A/GroupActivities` is clean-room. Apple's GroupActivities is closed source and pure Swift, and unlike Combine (OpenCombine) or CryptoKit (swift-crypto) it has no open-source twin to build from. `GroupActivities/Sources/GroupActivities.swift` therefore declares only the public API *shape*, recovered from the mangled names apps bind; no Apple code. Mangled names depend on the module name and the declared shape, so shape fidelity is the entire contract.

**Scope.** All 53 symbols Chess imports, verified with `llvm-nm -m --arch arm64e` against `Chess.app/Contents/MacOS/Chess` and diffed against the framework's export list. Chess is the motivating app; no other app's demand was derived, so the boundary may need widening. Every one of those imports is an eager, non-weak bind through `__DATA_CONST,__got`, so a single missing symbol stops the app loading at all.

The `Mp` protocol descriptor for `GroupActivity` is the load-bearing piece: Chess conforms its own type to it and emits a conformance record with resilient witnesses whose requirements resolve through GOT slots bound to the four `Tq` method descriptors and two `Tb` base conformance descriptors here. Nothing in this tree had previously emitted a protocol descriptor, and `swiftc` produces a correct one only because the source is real Swift rather than hand-written assembly.

**The three classes must stay `final`.** Under library evolution a non-final class member is emitted `private_extern` and reached through a `Tj` dispatch thunk, and ld64 then demotes the direct symbol to local. Apps bind the direct symbols and no `Tj` at all, so dropping `final` still builds and still links, but exports 44 of the 53 names and the app fails to load with no indication why.

**Deliberately inert.** SharePlay needs a coordination daemon Darling does not have, so this framework never produces a session: `isEligibleForGroupSession` is `false` and `activate()` returns `false`, which are the same answers real macOS gives outside a FaceTime call. `GroupSession.init` is private and traps, so no instance can exist, and every entry point that needs one (`join`, `leave`, `GroupSessionMessenger` and its `send`/`messages`) is therefore unreachable and traps rather than returning a fabricated session, participant or message. `sessions()` parks until cancelled rather than returning `nil`, because Apple's never terminates and reporting a completion it cannot emit would let callers run post-loop teardown that is unreachable on macOS.

**Known divergences from Apple, all of which fail loudly at load rather than silently.** `GroupActivityMetadata.ActivityType` declares only `.generic` (not `.watchTogether`/`.listenTogether`); `GroupStateObserver` is not `ObservableObject`, so there is no `$isEligibleForGroupSession` publisher; `GroupSessionMessenger.MessageContext` is empty. An app using any of those binds a symbol this dylib does not export and fails at load, which is the correct direction but is the next gap to close.

**Not verified.** This framework has never been loaded under Darling. The symbol set matches, which is necessary and not sufficient: no toolchain-built Swift framework in this repo has yet been shown to survive the Swift runtime's protocol-conformance registration under Darling's loader, and this is the first one to register a protocol descriptor at all. Chess also still cannot launch for unrelated reasons: 21 further eager binds are unresolved across MetalKit, ModelIO, AppKit, Metal, MetalPerformanceShaders and CoreFoundation.
