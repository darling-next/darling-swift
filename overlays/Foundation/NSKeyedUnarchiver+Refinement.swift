// Swift-only generic overlay for the NS_REFINED_FOR_SWIFT entry points declared in
// darling-foundation's NSKeyedArchiver.h, matching the public API shape of
// swift-corelibs-foundation's NSKeyedUnarchiver.swift (Apache License 2.0).

extension NSKeyedUnarchiver {
    @nonobjc
    public class func unarchivedObject<DecodedObjectType>(
        ofClass cls: DecodedObjectType.Type,
        from data: Data
    ) throws -> DecodedObjectType? where DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
        let object = try __unarchivedObject(ofClass: cls, fromData: data)
        return object as? DecodedObjectType
    }

    @nonobjc
    public class func unarchivedObject(
        ofClasses classes: [AnyClass],
        from data: Data
    ) throws -> Any? {
        // The refined ObjC entry point takes NSSet<Class> *, which the importer bridges to
        // Set<AnyHashable>; go through NSSet directly since AnyClass isn't Hashable in Swift.
        try __unarchivedObject(ofClasses: NSSet(array: classes) as! Set<AnyHashable>, fromData: data)
    }

    /// Decodes a top-level keyed archive without secure coding, the API released clients
    /// bind as `NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(_:)` (Prefire 5.6.1 and
    /// Sourcery 2.3.0 both bind it eagerly at launch). The Swift 6.2.4 payload this overlay
    /// replaces no longer defines it, but swift-corelibs-foundation's Darwin overlay does,
    /// and the declared behavior is that implementation's:
    ///
    ///   - Declaration: swift-corelibs-foundation
    ///     `Darwin/Foundation-swiftoverlay/NSCoder.swift`, `Data` overload, and the Xcode
    ///     26.3 Foundation.swiftinterface's `unarchiveTopLevelObjectWithData(_:) throws ->
    ///     Any?`.
    ///   - Route: darling-foundation's restored native
    ///     `+unarchiveTopLevelObjectWithData:error:`, the selector Apple's Foundation
    ///     declares for this API. It reads without secure coding, decodes
    ///     `NSKeyedArchiveRootObjectKey` through `-decodeTopLevelObjectForKey:error:`, and
    ///     reports a missing root as Cocoa 4865 (`NSCoderValueNotFoundError`). Invalid
    ///     bytes, including the coder's `NSInvalidUnarchiveOperationException` corrupt
    ///     path, report Cocoa 4864 (`NSCoderReadCorruptError`) instead of aborting, so the
    ///     Swift `throws` contract holds for the test-covered corrupt inputs.
    @nonobjc
    @available(macOS 10.11, iOS 9.0, *)
    public class func unarchiveTopLevelObjectWithData(_ data: Data) throws -> Any? {
        try __unarchiveTopLevelObjectWithData(data)
    }
}
