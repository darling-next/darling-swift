// UniformTypeIdentifiers Swift overlay for Darling, written from the framework's public Swift API (the
// UniformTypeIdentifiers.swiftinterface declarations apps are built against). UTType wraps an instance of
// Darling's Objective-C UTType, which holds the type table, conformances and tag lookups; every member here
// forwards to it. Built with library evolution, so apps reach UTType only through these symbols.
//
// Not included: the URL, String and NSItemProvider extensions, macOS 26's referenceAccessoryURL
// and setDefaultHandler(to:completionHandler:), and the static types whose Objective-C constants Darling does not
// export yet (css, heics, exr, dng, jpegxl, tarArchive, ahap, geoJSON, linkPresentationMetadata).

import Foundation
// Re-export the UniformTypeIdentifiers Clang module (UTTypeReference and the UTType* constants) where the SDK
// has one, so clients need no private module map; otherwise take the declarations from the shim. build.sh sets
// the flag, as for QuartzCore.
#if DARLING_UNIFORMTYPEIDENTIFIERS_CLANG_MODULE
@_exported import UniformTypeIdentifiers
#else
import _DarlingUniformTypeIdentifiersShims
#endif

public struct UTType: @unchecked Sendable {
	internal let _reference: UTTypeReference

	internal init(_reference: UTTypeReference) {
		self._reference = _reference
	}
}

extension UTType {
	public init?(_ identifier: String) {
		guard let reference = UTTypeReference(identifier: identifier) else { return nil }
		self.init(_reference: reference)
	}

	public init?(filenameExtension: String, conformingTo supertype: UTType = .data) {
		guard let reference = UTTypeReference(filenameExtension: filenameExtension, conformingTo: supertype._reference) else { return nil }
		self.init(_reference: reference)
	}

	public init?(mimeType: String, conformingTo supertype: UTType = .data) {
		guard let reference = UTTypeReference(mimeType: mimeType, conformingTo: supertype._reference) else { return nil }
		self.init(_reference: reference)
	}

	public var identifier: String { _reference.identifier }
	public var preferredFilenameExtension: String? { _reference.preferredFilenameExtension }
	public var preferredMIMEType: String? { _reference.preferredMIMEType }
	public var localizedDescription: String? { _reference.localizedDescription }
	public var version: Int? { _reference.typeVersion?.integerValue() }
	public var referenceURL: URL? { _reference.referenceURL.map { $0 as URL } }
	public var isDynamic: Bool { _reference.isDynamic }
	public var isDeclared: Bool { _reference.isDeclared }
	public var isPublic: Bool { _reference.isPublicType }
}

extension UTType {
	public func conforms(to type: UTType) -> Bool { _reference.conforms(to: type._reference) }
	public func isSupertype(of type: UTType) -> Bool { _reference.isSupertype(of: type._reference) }
	public func isSubtype(of type: UTType) -> Bool { _reference.isSubtype(of: type._reference) }

	public var supertypes: Set<UTType> {
		Set(_reference.supertypes.map { UTType(_reference: $0) })
	}
}

extension UTType {
	public init?(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) {
		guard let reference = UTTypeReference(tag: tag, tagClass: tagClass.rawValue, conformingTo: supertype?._reference) else { return nil }
		self.init(_reference: reference)
	}

	public static func types(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) -> [UTType] {
		UTTypeReference.types(withTag: tag, tagClass: tagClass.rawValue, conformingTo: supertype?._reference).map { UTType(_reference: $0) }
	}

	public var tags: [UTTagClass: [String]] {
		var result: [UTTagClass: [String]] = [:]
		for (tagClass, tags) in _reference.tags {
			result[UTTagClass(rawValue: tagClass)] = tags
		}
		return result
	}
}

extension UTType {
	public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) {
		if let parentType {
			self.init(_reference: UTTypeReference.exportedType(withIdentifier: identifier, conformingTo: parentType._reference))
		} else {
			self.init(_reference: UTTypeReference.exportedType(withIdentifier: identifier))
		}
	}

	public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) {
		if let parentType {
			self.init(_reference: UTTypeReference.importedType(withIdentifier: identifier, conformingTo: parentType._reference))
		} else {
			self.init(_reference: UTTypeReference.importedType(withIdentifier: identifier))
		}
	}
}

extension UTType: Equatable, Hashable {
	public static func == (lhs: UTType, rhs: UTType) -> Bool { lhs._reference.isEqual(rhs._reference) }
	public func hash(into hasher: inout Hasher) { hasher.combine(_reference.hash) }
}

extension UTType: CustomStringConvertible, CustomDebugStringConvertible {
	public var description: String { identifier }
	public var debugDescription: String { _reference.debugDescription }
}

extension UTType: ReferenceConvertible {
	public typealias ReferenceType = UTTypeReference

	public func _bridgeToObjectiveC() -> UTTypeReference { _reference }

	public static func _forceBridgeFromObjectiveC(_ source: UTTypeReference, result: inout UTType?) {
		result = UTType(_reference: source)
	}

	public static func _conditionallyBridgeFromObjectiveC(_ source: UTTypeReference, result: inout UTType?) -> Bool {
		result = UTType(_reference: source)
		return true
	}

	public static func _unconditionallyBridgeFromObjectiveC(_ source: UTTypeReference?) -> UTType {
		UTType(_reference: source!)
	}
}

extension UTType: Codable {
	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(identifier)
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		let identifier = try container.decode(String.self)
		guard let type = UTType(identifier) else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(identifier) is not a valid type identifier")
		}
		self = type
	}
}

extension URLResourceValues {
	// The key is built from its raw value instead of naming the SDK's `NSURLContentTypeKey` constant.
	// No image in the guest defines that constant: Darling's Foundation headers declare it
	// (src/external/foundation/include/Foundation/NSURL.h) and the Foundation re-export list carries
	// it, but neither the deployed Foundation nor the freshly built one nor CoreFoundation has the
	// symbol, so naming it links against a symbol the guest cannot resolve -- a load-time dependency
	// this overlay must not add.  The raw value is the constant's name, which is the convention every
	// sibling key in this tree follows (src/external/corefoundation/NSURL.m defines
	// `NSString *const NSURLNameKey = @"NSURLNameKey";`, its CFURLConstants.c twin does the same, and
	// swift-corelibs-foundation builds them the same way: `URLResourceKey(rawValue: "NSURLNameKey")`).
	// The missing definition belongs in CoreFoundation, next to those keys; until it lands, this line
	// keeps the overlay loadable and the lookup honest: a guest whose Foundation does not carry the
	// content-type key has no content type to report.
	public var contentType: UTType? {
		let key = URLResourceKey(rawValue: "NSURLContentTypeKey")
		return (allValues[key] as? UTTypeReference).map { UTType(_reference: $0) }
	}
}

extension URL {
	/// Returns a URL by appending the preferred path extension for the type to the URL's last path
	/// component.
	///
	/// This one member of Apple's `URL`/`String`/`NSItemProvider` UTI extensions is required, not
	/// optional: the guest's Xcode 26.3 `XCResultKit` binds it NON-weakly from
	/// libswiftUniformTypeIdentifiers inside `libxcodebuildLoader`'s load closure, so without the
	/// symbol that image cannot load (scripts/closure_analyze.py reports it as the component's only
	/// missing demanded symbol).  The other three URL members stay out: nothing in the closure demands
	/// them.
	///
	/// Apple's documentation is what the body follows: "a new URL with the type's preferred extension
	/// appended"; a type with no preferred extension has none to append and the URL is returned
	/// unchanged, which is also Apple's documented answer when the extension cannot be appended.
	public func appendingPathExtension(for contentType: UTType) -> URL {
		guard let preferredExtension = contentType.preferredFilenameExtension else { return self }
		return appendingPathExtension(preferredExtension)
	}
}

extension UTType {
	public static var item: UTType { UTType(_reference: UTTypeItem) }
	public static var content: UTType { UTType(_reference: UTTypeContent) }
	public static var compositeContent: UTType { UTType(_reference: UTTypeCompositeContent) }
	public static var diskImage: UTType { UTType(_reference: UTTypeDiskImage) }
	public static var data: UTType { UTType(_reference: UTTypeData) }
	public static var directory: UTType { UTType(_reference: UTTypeDirectory) }
	public static var resolvable: UTType { UTType(_reference: UTTypeResolvable) }
	public static var symbolicLink: UTType { UTType(_reference: UTTypeSymbolicLink) }
	public static var executable: UTType { UTType(_reference: UTTypeExecutable) }
	public static var mountPoint: UTType { UTType(_reference: UTTypeMountPoint) }
	public static var aliasFile: UTType { UTType(_reference: UTTypeAliasFile) }
	public static var urlBookmarkData: UTType { UTType(_reference: UTTypeURLBookmarkData) }
	public static var url: UTType { UTType(_reference: UTTypeURL) }
	public static var fileURL: UTType { UTType(_reference: UTTypeFileURL) }
	public static var text: UTType { UTType(_reference: UTTypeText) }
	public static var plainText: UTType { UTType(_reference: UTTypePlainText) }
	public static var utf8PlainText: UTType { UTType(_reference: UTTypeUTF8PlainText) }
	public static var utf16ExternalPlainText: UTType { UTType(_reference: UTTypeUTF16ExternalPlainText) }
	public static var utf16PlainText: UTType { UTType(_reference: UTTypeUTF16PlainText) }
	public static var delimitedText: UTType { UTType(_reference: UTTypeDelimitedText) }
	public static var commaSeparatedText: UTType { UTType(_reference: UTTypeCommaSeparatedText) }
	public static var tabSeparatedText: UTType { UTType(_reference: UTTypeTabSeparatedText) }
	public static var utf8TabSeparatedText: UTType { UTType(_reference: UTTypeUTF8TabSeparatedText) }
	public static var rtf: UTType { UTType(_reference: UTTypeRTF) }
	public static var html: UTType { UTType(_reference: UTTypeHTML) }
	public static var xml: UTType { UTType(_reference: UTTypeXML) }
	public static var yaml: UTType { UTType(_reference: UTTypeYAML) }
	public static var sourceCode: UTType { UTType(_reference: UTTypeSourceCode) }
	public static var assemblyLanguageSource: UTType { UTType(_reference: UTTypeAssemblyLanguageSource) }
	public static var cSource: UTType { UTType(_reference: UTTypeCSource) }
	public static var objectiveCSource: UTType { UTType(_reference: UTTypeObjectiveCSource) }
	public static var swiftSource: UTType { UTType(_reference: UTTypeSwiftSource) }
	public static var cPlusPlusSource: UTType { UTType(_reference: UTTypeCPlusPlusSource) }
	public static var objectiveCPlusPlusSource: UTType { UTType(_reference: UTTypeObjectiveCPlusPlusSource) }
	public static var cHeader: UTType { UTType(_reference: UTTypeCHeader) }
	public static var cPlusPlusHeader: UTType { UTType(_reference: UTTypeCPlusPlusHeader) }
	public static var script: UTType { UTType(_reference: UTTypeScript) }
	public static var appleScript: UTType { UTType(_reference: UTTypeAppleScript) }
	public static var osaScript: UTType { UTType(_reference: UTTypeOSAScript) }
	public static var osaScriptBundle: UTType { UTType(_reference: UTTypeOSAScriptBundle) }
	public static var javaScript: UTType { UTType(_reference: UTTypeJavaScript) }
	public static var shellScript: UTType { UTType(_reference: UTTypeShellScript) }
	public static var perlScript: UTType { UTType(_reference: UTTypePerlScript) }
	public static var pythonScript: UTType { UTType(_reference: UTTypePythonScript) }
	public static var rubyScript: UTType { UTType(_reference: UTTypeRubyScript) }
	public static var phpScript: UTType { UTType(_reference: UTTypePHPScript) }
	public static var makefile: UTType { UTType(_reference: UTTypeMakefile) }
	public static var json: UTType { UTType(_reference: UTTypeJSON) }
	public static var propertyList: UTType { UTType(_reference: UTTypePropertyList) }
	public static var xmlPropertyList: UTType { UTType(_reference: UTTypeXMLPropertyList) }
	public static var binaryPropertyList: UTType { UTType(_reference: UTTypeBinaryPropertyList) }
	public static var pdf: UTType { UTType(_reference: UTTypePDF) }
	public static var rtfd: UTType { UTType(_reference: UTTypeRTFD) }
	public static var flatRTFD: UTType { UTType(_reference: UTTypeFlatRTFD) }
	public static var webArchive: UTType { UTType(_reference: UTTypeWebArchive) }
	public static var image: UTType { UTType(_reference: UTTypeImage) }
	public static var jpeg: UTType { UTType(_reference: UTTypeJPEG) }
	public static var tiff: UTType { UTType(_reference: UTTypeTIFF) }
	public static var gif: UTType { UTType(_reference: UTTypeGIF) }
	public static var png: UTType { UTType(_reference: UTTypePNG) }
	public static var icns: UTType { UTType(_reference: UTTypeICNS) }
	public static var bmp: UTType { UTType(_reference: UTTypeBMP) }
	public static var ico: UTType { UTType(_reference: UTTypeICO) }
	public static var rawImage: UTType { UTType(_reference: UTTypeRAWImage) }
	public static var svg: UTType { UTType(_reference: UTTypeSVG) }
	public static var livePhoto: UTType { UTType(_reference: UTTypeLivePhoto) }
	public static var heif: UTType { UTType(_reference: UTTypeHEIF) }
	public static var heic: UTType { UTType(_reference: UTTypeHEIC) }
	public static var webP: UTType { UTType(_reference: UTTypeWebP) }
	public static var threeDContent: UTType { UTType(_reference: UTType3DContent) }
	public static var usd: UTType { UTType(_reference: UTTypeUSD) }
	public static var usdz: UTType { UTType(_reference: UTTypeUSDZ) }
	public static var realityFile: UTType { UTType(_reference: UTTypeRealityFile) }
	public static var sceneKitScene: UTType { UTType(_reference: UTTypeSceneKitScene) }
	public static var arReferenceObject: UTType { UTType(_reference: UTTypeARReferenceObject) }
	public static var audiovisualContent: UTType { UTType(_reference: UTTypeAudiovisualContent) }
	public static var movie: UTType { UTType(_reference: UTTypeMovie) }
	public static var video: UTType { UTType(_reference: UTTypeVideo) }
	public static var audio: UTType { UTType(_reference: UTTypeAudio) }
	public static var quickTimeMovie: UTType { UTType(_reference: UTTypeQuickTimeMovie) }
	public static var mpeg: UTType { UTType(_reference: UTTypeMPEG) }
	public static var mpeg2Video: UTType { UTType(_reference: UTTypeMPEG2Video) }
	public static var mpeg2TransportStream: UTType { UTType(_reference: UTTypeMPEG2TransportStream) }
	public static var mp3: UTType { UTType(_reference: UTTypeMP3) }
	public static var mpeg4Movie: UTType { UTType(_reference: UTTypeMPEG4Movie) }
	public static var mpeg4Audio: UTType { UTType(_reference: UTTypeMPEG4Audio) }
	public static var appleProtectedMPEG4Audio: UTType { UTType(_reference: UTTypeAppleProtectedMPEG4Audio) }
	public static var appleProtectedMPEG4Video: UTType { UTType(_reference: UTTypeAppleProtectedMPEG4Video) }
	public static var avi: UTType { UTType(_reference: UTTypeAVI) }
	public static var aiff: UTType { UTType(_reference: UTTypeAIFF) }
	public static var wav: UTType { UTType(_reference: UTTypeWAV) }
	public static var midi: UTType { UTType(_reference: UTTypeMIDI) }
	public static var playlist: UTType { UTType(_reference: UTTypePlaylist) }
	public static var m3uPlaylist: UTType { UTType(_reference: UTTypeM3UPlaylist) }
	public static var folder: UTType { UTType(_reference: UTTypeFolder) }
	public static var volume: UTType { UTType(_reference: UTTypeVolume) }
	public static var package: UTType { UTType(_reference: UTTypePackage) }
	public static var bundle: UTType { UTType(_reference: UTTypeBundle) }
	public static var pluginBundle: UTType { UTType(_reference: UTTypePluginBundle) }
	public static var spotlightImporter: UTType { UTType(_reference: UTTypeSpotlightImporter) }
	public static var quickLookGenerator: UTType { UTType(_reference: UTTypeQuickLookGenerator) }
	public static var xpcService: UTType { UTType(_reference: UTTypeXPCService) }
	public static var framework: UTType { UTType(_reference: UTTypeFramework) }
	public static var application: UTType { UTType(_reference: UTTypeApplication) }
	public static var applicationBundle: UTType { UTType(_reference: UTTypeApplicationBundle) }
	public static var applicationExtension: UTType { UTType(_reference: UTTypeApplicationExtension) }
	public static var unixExecutable: UTType { UTType(_reference: UTTypeUnixExecutable) }
	public static var exe: UTType { UTType(_reference: UTTypeEXE) }
	public static var systemPreferencesPane: UTType { UTType(_reference: UTTypeSystemPreferencesPane) }
	public static var archive: UTType { UTType(_reference: UTTypeArchive) }
	public static var gzip: UTType { UTType(_reference: UTTypeGZIP) }
	public static var bz2: UTType { UTType(_reference: UTTypeBZ2) }
	public static var zip: UTType { UTType(_reference: UTTypeZIP) }
	public static var appleArchive: UTType { UTType(_reference: UTTypeAppleArchive) }
	public static var spreadsheet: UTType { UTType(_reference: UTTypeSpreadsheet) }
	public static var presentation: UTType { UTType(_reference: UTTypePresentation) }
	public static var database: UTType { UTType(_reference: UTTypeDatabase) }
	public static var message: UTType { UTType(_reference: UTTypeMessage) }
	public static var contact: UTType { UTType(_reference: UTTypeContact) }
	public static var vCard: UTType { UTType(_reference: UTTypeVCard) }
	public static var toDoItem: UTType { UTType(_reference: UTTypeToDoItem) }
	public static var calendarEvent: UTType { UTType(_reference: UTTypeCalendarEvent) }
	public static var emailMessage: UTType { UTType(_reference: UTTypeEmailMessage) }
	public static var internetLocation: UTType { UTType(_reference: UTTypeInternetLocation) }
	public static var internetShortcut: UTType { UTType(_reference: UTTypeInternetShortcut) }
	public static var font: UTType { UTType(_reference: UTTypeFont) }
	public static var bookmark: UTType { UTType(_reference: UTTypeBookmark) }
	public static var pkcs12: UTType { UTType(_reference: UTTypePKCS12) }
	public static var x509Certificate: UTType { UTType(_reference: UTTypeX509Certificate) }
	public static var epub: UTType { UTType(_reference: UTTypeEPUB) }
	public static var log: UTType { UTType(_reference: UTTypeLog) }
}

public struct UTTagClass: RawRepresentable {
	public let rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}

	public typealias RawValue = String
}

extension UTTagClass {
	public static var filenameExtension: UTTagClass { UTTagClass(rawValue: UTTagClassFilenameExtension) }
	public static var mimeType: UTTagClass { UTTagClass(rawValue: UTTagClassMIMEType) }
}

extension UTTagClass: Equatable, Hashable {
	public static func == (lhs: UTTagClass, rhs: UTTagClass) -> Bool { lhs.rawValue == rhs.rawValue }
	public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

extension UTTagClass: CustomStringConvertible, CustomDebugStringConvertible {
	public var description: String { rawValue }
	public var debugDescription: String { rawValue }
}

extension UTTagClass: Codable {
	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}

	public init(from decoder: any Decoder) throws {
		self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
	}
}

// MARK: - Hardware types (the macOS 26 API the Xcode 26.3 XCTHarness binds)

// Xcode 26.3's libswiftUniformTypeIdentifiers (current version 877.2.4) exports UTHardwareColor and
// UTType.init?(_deviceModelCode:enclosureColor:), and the guest's XCTHarness binds three of those
// names NON-weakly -- UTHardwareColor's metadata accessor and nominal type descriptor, and the
// initializer -- so an overlay that stops at the pre-26 API leaves XCTHarness's load command
// unsatisfied.  The declarations below follow Apple's own .tbd for the library, which is the ABI:
// it names the enum's two payload cases (rgb with three UInt8 components, indexed with an Int32),
// its Equatable/Hashable/Encodable/Decodable conformances and their descriptors, hashValue and
// hash(into:), currentEnclosureColor, and the initializer.  The enum is plain data and is implemented
// in full: equality, hashing and Codable are the compiler's synthesis, as on the platform Apple ships.

/// The colour of a device's enclosure (macOS 26), as a Swift value: either 8-bit RGB components or an
/// index into the platform's colour table.
public enum UTHardwareColor: Equatable, Hashable, Codable {
	/// A colour given by its red, green and blue components.
	case rgb(UInt8, UInt8, UInt8)
	/// A colour given by its index in the platform's colour table.
	case indexed(Int32)

	/// The enclosure colour of the current device, or `nil` when the platform has none to report.
	///
	/// `nil` is this platform's own answer rather than a placeholder: Darling's Objective-C
	/// UniformTypeIdentifiers carries Apple's private backing entry point as a stub that reports
	/// absence (`_UTHardwareColorGetCurrentEnclosureColor` returns NULL --
	/// src/frameworks/UniformTypeIdentifiers/src/UniformTypeIdentifiers.m), and this guest runs on no
	/// Apple hardware to ask.
	public static var currentEnclosureColor: UTHardwareColor? { nil }
}

extension UTType {
	/// The type for the device whose model code this is, or `nil` when no such type exists.
	///
	/// It is always `nil` here, and that is this platform's answer: Apple resolves the code through
	/// the device-model-code tag class, and Darling's Objective-C UniformTypeIdentifiers has no such
	/// tag class (`_UTTagClassDeviceModelCode` is NULL in the framework's own source), so a lookup
	/// that needs it finds nothing.  The initializer exists because XCTHarness binds its symbol.
	public init?(_deviceModelCode: String, enclosureColor: UTHardwareColor?) {
		return nil
	}
}
