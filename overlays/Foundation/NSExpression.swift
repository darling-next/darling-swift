//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Darling: the KeyPath initializer of NSExpression -- Apple declares it in module Foundation, and
// the overlay of this tree never carried it, because this file was not among the release/5.4
// stdlib/public/Darwin/Foundation files the overlay was built from.
//
// WHY THIS DECLARATION EXISTS (the rung that needed it). Xcode 26.3's
// Contents/SharedFrameworks/DVTFoundation.framework binds, eagerly and strongly,
//
//     _$sSo12NSExpressionC10FoundationE10forKeyPathABs0dE0Cyxq_G_tcr0_lufC
//       == (extension in Foundation): __C.NSExpression.init<A, B>(forKeyPath: Swift.KeyPath<A, B>)
//                                                    -> __C.NSExpression
//
// against its Foundation ordinal, and the deployed /usr/lib/swift/libswiftFoundation.dylib exported
// no NSExpression Swift symbol at all, so the guest's dyld stopped at
//
//     Error loading required libraries. If there is an ongoing installation please wait for it to
//     complete. Otherwise reinstall. (dlopen(@rpath/libxcodebuildLoader.dylib, 1):
//       Symbol not found: _$sSS10FoundationE5bytes8encodingSSSgxh_SSAAE8EncodingVtcSTRzs5UInt8V7ElementRtzlufC
//       Referenced from: .../SharedFrameworks/DVTFoundation.framework/Versions/A/DVTFoundation
//         (which was built for Mac OS X 14.0)
//       Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
//     )                                                                  [measured 2026-10-12]
//
// (that run's first stop was the String init in NSStringAPI.swift; this image demands four symbols
// of this module and the loader resolves them one rung at a time). "Expected in:
// .../Foundation.framework/..." is the ordinal's blame text, not the file that must change:
// Darling's Foundation.framework is the Objective-C framework, it re-exports
// /usr/lib/swift/libswiftFoundation.dylib, and this module is that dylib.
//
// WHAT THE CLIENT DOES WITH IT (measured from the demanding image's own bind table and its
// disassembly, not assumed). The one symbol it binds for this API is the generic entry point above;
// it binds no specialization of it -- the call at DVTFoundation 0x2f1e5c is inside
// `_$sSo8NSObjectP13DVTFoundationSoAACRbzrlE21dvt_newSharedObserver10forKeyPath14observeInitial16withHandlerBlock...`,
// the Swift extension `NSObject.dvt_newSharedObserver<Root>(forKeyPath:observeInitial:withHandlerBlock:)`,
// and it passes the `KeyPath<Root, Value>` the caller handed that extension. The result is retained
// (`_objc_retainAutoreleasedReturnValue`) and passed straight to an Objective-C message, so a
// returned expression is used as an `NSExpression` object and nothing about it is read in Swift.
//
// WHERE EVERYTHING COMES FROM (nothing here is invented):
//
//   * The DECLARATION is Apple's published API for this module, read out of the guest's own SDK:
//       <Xcode 26.3>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/
//         Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/x86_64-apple-macos.swiftinterface
//     (line 20014: `extension Foundation.NSExpression { convenience public init<Root, Value>(forKeyPath
//     keyPath: Swift.KeyPath<Root, Value>) }`).
//
//   * The BODY is Apple's own open source for this exact API, module name and licence:
//     swiftlang/swift release/5.4 stdlib/public/Darwin/Foundation/NSExpression.swift:
//
//         extension NSExpression {
//             public convenience init<Root, Value>(forKeyPath keyPath: KeyPath<Root, Value>) {
//                 self.init(forKeyPath: _bridgeKeyPathToString(keyPath))
//             }
//         }
//
//     `_bridgeKeyPathToString` is already in this module -- Foundation/NSObject.swift:47, taken from
//     the same release's NSObject.swift:154 --
//
//         func _bridgeKeyPathToString(_ keyPath: AnyKeyPath) -> String {
//             guard let keyPathString = keyPath._kvcKeyPathString else {
//                 fatalError("Could not extract a String from KeyPath \(keyPath)")
//             }
//             return keyPathString
//         }
//
//     so a key path with no KVC string cannot silently become an empty or invented one: it TRAPS with
//     that message, which is Apple's own measured behaviour for this initializer
//     (`NSExpression(forKeyPath: \String.count)` -> "Thread 1: Fatal error: Could not extract a
//     String from KeyPath Swift.KeyPath<Swift.String, Swift.Int>", swift-corelibs-foundation
//     issue #4085). The KeyPath -> String conversion itself is the standard library's
//     `AnyKeyPath._kvcKeyPathString`, whose own header documents it as "SPI for the Foundation
//     overlay to allow interop with KVC keypath-based APIs" (swiftlang/swift
//     stdlib/public/core/KeyPath.swift).
//
//   * `self.init(forKeyPath:)` is Darling's Objective-C `+[NSExpression expressionForKeyPath:]`
//     (src/external/foundation/src/NSExpression.m:62), which builds a real NSKeyPathExpression; it
//     imports into Swift as `NSExpression(forKeyPath: String)` through the Clang importer's factory
//     method rule. That path is a real implementation, not a stub.
//
// WHAT IS DELIBERATELY NOT HERE. The other declaration that release/5.4's NSExpression.swift
// carries, `init(format: _ args: CVarArg...)`: no image in this closure demands its symbol, so it is
// not added here (grep of the coverage graph's unmet demands for `So12NSExpression` finds this
// initializer alone). It is Apple open source and a later rung may take it the same way.

@_exported import Foundation // Clang module

extension NSExpression {
    public convenience init<Root, Value>(forKeyPath keyPath: KeyPath<Root, Value>) {
        self.init(forKeyPath: _bridgeKeyPathToString(keyPath))
    }
}
