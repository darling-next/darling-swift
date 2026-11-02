// Darling: the Swift bridging keyed subscript on a bridged NSDictionary sends
// `__swift_objectForKeyedSubscript:`. On Darwin that method is implemented by Foundation's Swift
// overlay (swift-corelibs-foundation carries the same getter in
// Darwin/Foundation-swiftoverlay/NSDictionary.swift, `@objc(__swift_objectForKeyedSubscript:)`), and
// nothing in this tree implemented it: the deployed CoreFoundation has the plain
// `-[NSDictionary(NSExtendedDictionary) objectForKeyedSubscript:]` but no `__swift_` variant, and
// neither the deployed Foundation nor this overlay had the selector.
//
// Measured consequence (SWBBuildService's own core, 2026-10-15): SwiftBuild's build service died of an
// uncaught NSException while registering its SDKs --
//   SWBUtil  PropertyList.decode(_:from:) <- NSPropertyListSerialization.swb_stableData(fromPropertyList:...)
//   SWBCore  SDKVariant.init(name:settings:supportedTargetDict:) <- SDKRegistry.registerSDK(...)
// -- because the first `dict[key]` on a bridged NSDictionary raised
//   '-[__NSCFDictionary __swift_objectForKeyedSubscript:]: unrecognized selector sent to instance ...'
// and std::terminate ran inside a dispatch callout.
//
// Body is upstream's, behaviour for behaviour: the subscript forwards to object(forKey:).
extension NSDictionary {
  @objc(__swift_objectForKeyedSubscript:)
  public func __swift_object(forKeyedSubscript key: Any) -> Any? {
    return self.object(forKey: key)
  }
}
