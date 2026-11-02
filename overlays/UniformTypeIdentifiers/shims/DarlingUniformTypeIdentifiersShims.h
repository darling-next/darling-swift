// Declarations of Darling's Objective-C UTType (src/frameworks/UniformTypeIdentifiers in darling) that the
// UniformTypeIdentifiers Swift overlay wraps. The SDK the overlays are built against has no Clang module for
// the framework. As in Apple's SDK, the class is renamed UTTypeReference for Swift so that it does not clash
// with the overlay's UTType struct; its symbols keep their Objective-C names (`So6UTTypeC`).
#ifndef DARLING_UNIFORMTYPEIDENTIFIERS_SHIMS_H
#define DARLING_UNIFORMTYPEIDENTIFIERS_SHIMS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

__attribute__((swift_name("UTTypeReference")))
@interface UTType : NSObject <NSCopying, NSSecureCoding>
- (instancetype)init NS_UNAVAILABLE;
+ (nullable UTType *)typeWithIdentifier:(NSString *)identifier;
+ (nullable UTType *)typeWithFilenameExtension:(NSString *)filenameExtension conformingToType:(UTType *)supertype;
+ (nullable UTType *)typeWithMIMEType:(NSString *)mimeType conformingToType:(UTType *)supertype;
+ (nullable UTType *)typeWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(nullable UTType *)supertype;
+ (NSArray<UTType *> *)typesWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(nullable UTType *)supertype;
+ (UTType *)exportedTypeWithIdentifier:(NSString *)identifier;
+ (UTType *)exportedTypeWithIdentifier:(NSString *)identifier conformingToType:(UTType *)parentType;
+ (UTType *)importedTypeWithIdentifier:(NSString *)identifier;
+ (UTType *)importedTypeWithIdentifier:(NSString *)identifier conformingToType:(UTType *)parentType;
@property (readonly, copy) NSString *identifier;
@property (readonly, nullable, copy) NSString *preferredFilenameExtension;
@property (readonly, nullable, copy) NSString *preferredMIMEType;
@property (readonly, nullable, copy) NSString *localizedDescription;
@property (readonly, nullable, copy) NSNumber *version __attribute__((swift_name("typeVersion")));
@property (readonly, nullable, copy) NSURL *referenceURL;
@property (readonly, getter=isDynamic) BOOL dynamic;
@property (readonly, getter=isDeclared) BOOL declared;
@property (readonly, getter=isPublicType) BOOL publicType;
@property (readonly) NSDictionary<NSString *, NSArray<NSString *> *> *tags;
@property (readonly, copy) NSSet<UTType *> *supertypes;
- (BOOL)conformsToType:(UTType *)type;
- (BOOL)isSupertypeOfType:(UTType *)type;
- (BOOL)isSubtypeOfType:(UTType *)type;
@end

extern NSString *const UTTagClassFilenameExtension;
extern NSString *const UTTagClassMIMEType;

extern UTType *const UTType3DContent;
extern UTType *const UTTypeAIFF;
extern UTType *const UTTypeARReferenceObject;
extern UTType *const UTTypeAVI;
extern UTType *const UTTypeAliasFile;
extern UTType *const UTTypeAppleArchive;
extern UTType *const UTTypeAppleProtectedMPEG4Audio;
extern UTType *const UTTypeAppleProtectedMPEG4Video;
extern UTType *const UTTypeAppleScript;
extern UTType *const UTTypeApplication;
extern UTType *const UTTypeApplicationBundle;
extern UTType *const UTTypeApplicationExtension;
extern UTType *const UTTypeArchive;
extern UTType *const UTTypeAssemblyLanguageSource;
extern UTType *const UTTypeAudio;
extern UTType *const UTTypeAudiovisualContent;
extern UTType *const UTTypeBMP;
extern UTType *const UTTypeBZ2;
extern UTType *const UTTypeBinaryPropertyList;
extern UTType *const UTTypeBookmark;
extern UTType *const UTTypeBundle;
extern UTType *const UTTypeCHeader;
extern UTType *const UTTypeCPlusPlusHeader;
extern UTType *const UTTypeCPlusPlusSource;
extern UTType *const UTTypeCSource;
extern UTType *const UTTypeCalendarEvent;
extern UTType *const UTTypeCommaSeparatedText;
extern UTType *const UTTypeCompositeContent;
extern UTType *const UTTypeContact;
extern UTType *const UTTypeContent;
extern UTType *const UTTypeData;
extern UTType *const UTTypeDatabase;
extern UTType *const UTTypeDelimitedText;
extern UTType *const UTTypeDirectory;
extern UTType *const UTTypeDiskImage;
extern UTType *const UTTypeEPUB;
extern UTType *const UTTypeEXE;
extern UTType *const UTTypeEmailMessage;
extern UTType *const UTTypeExecutable;
extern UTType *const UTTypeFileURL;
extern UTType *const UTTypeFlatRTFD;
extern UTType *const UTTypeFolder;
extern UTType *const UTTypeFont;
extern UTType *const UTTypeFramework;
extern UTType *const UTTypeGIF;
extern UTType *const UTTypeGZIP;
extern UTType *const UTTypeHEIC;
extern UTType *const UTTypeHEIF;
extern UTType *const UTTypeHTML;
extern UTType *const UTTypeICNS;
extern UTType *const UTTypeICO;
extern UTType *const UTTypeImage;
extern UTType *const UTTypeInternetLocation;
extern UTType *const UTTypeInternetShortcut;
extern UTType *const UTTypeItem;
extern UTType *const UTTypeJPEG;
extern UTType *const UTTypeJSON;
extern UTType *const UTTypeJavaScript;
extern UTType *const UTTypeLivePhoto;
extern UTType *const UTTypeLog;
extern UTType *const UTTypeM3UPlaylist;
extern UTType *const UTTypeMIDI;
extern UTType *const UTTypeMP3;
extern UTType *const UTTypeMPEG2TransportStream;
extern UTType *const UTTypeMPEG2Video;
extern UTType *const UTTypeMPEG4Audio;
extern UTType *const UTTypeMPEG4Movie;
extern UTType *const UTTypeMPEG;
extern UTType *const UTTypeMakefile;
extern UTType *const UTTypeMessage;
extern UTType *const UTTypeMountPoint;
extern UTType *const UTTypeMovie;
extern UTType *const UTTypeOSAScript;
extern UTType *const UTTypeOSAScriptBundle;
extern UTType *const UTTypeObjectiveCPlusPlusSource;
extern UTType *const UTTypeObjectiveCSource;
extern UTType *const UTTypePDF;
extern UTType *const UTTypePHPScript;
extern UTType *const UTTypePKCS12;
extern UTType *const UTTypePNG;
extern UTType *const UTTypePackage;
extern UTType *const UTTypePerlScript;
extern UTType *const UTTypePlainText;
extern UTType *const UTTypePlaylist;
extern UTType *const UTTypePluginBundle;
extern UTType *const UTTypePresentation;
extern UTType *const UTTypePropertyList;
extern UTType *const UTTypePythonScript;
extern UTType *const UTTypeQuickLookGenerator;
extern UTType *const UTTypeQuickTimeMovie;
extern UTType *const UTTypeRAWImage;
extern UTType *const UTTypeRTF;
extern UTType *const UTTypeRTFD;
extern UTType *const UTTypeRealityFile;
extern UTType *const UTTypeResolvable;
extern UTType *const UTTypeRubyScript;
extern UTType *const UTTypeSVG;
extern UTType *const UTTypeSceneKitScene;
extern UTType *const UTTypeScript;
extern UTType *const UTTypeShellScript;
extern UTType *const UTTypeSourceCode;
extern UTType *const UTTypeSpotlightImporter;
extern UTType *const UTTypeSpreadsheet;
extern UTType *const UTTypeSwiftSource;
extern UTType *const UTTypeSymbolicLink;
extern UTType *const UTTypeSystemPreferencesPane;
extern UTType *const UTTypeTIFF;
extern UTType *const UTTypeTabSeparatedText;
extern UTType *const UTTypeText;
extern UTType *const UTTypeToDoItem;
extern UTType *const UTTypeURL;
extern UTType *const UTTypeURLBookmarkData;
extern UTType *const UTTypeUSD;
extern UTType *const UTTypeUSDZ;
extern UTType *const UTTypeUTF16ExternalPlainText;
extern UTType *const UTTypeUTF16PlainText;
extern UTType *const UTTypeUTF8PlainText;
extern UTType *const UTTypeUTF8TabSeparatedText;
extern UTType *const UTTypeUnixExecutable;
extern UTType *const UTTypeVCard;
extern UTType *const UTTypeVideo;
extern UTType *const UTTypeVolume;
extern UTType *const UTTypeWAV;
extern UTType *const UTTypeWebArchive;
extern UTType *const UTTypeWebP;
extern UTType *const UTTypeX509Certificate;
extern UTType *const UTTypeXML;
extern UTType *const UTTypeXMLPropertyList;
extern UTType *const UTTypeXPCService;
extern UTType *const UTTypeYAML;
extern UTType *const UTTypeZIP;

NS_ASSUME_NONNULL_END

#endif
