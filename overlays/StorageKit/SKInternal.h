/*
 * StorageKit substitute: the measured class surface CoreDevice binds, backed by a
 * real hdiutil attach/mount and a manager record for the mounted disk.
 *
 * The class and selector shapes come from the field CoreDevice consumer:
 *   evidence/coredevice-storagekit-calls-20261025bb-monitor
 *   SKDiskImage initWithURL:error:
 *   SKDiskImageAttachParams init / setIsManagedAttach: / mountParams
 *   SKMountParams setReadOnly: / setNoBrowse: / setAllParams: / setMountPoint:
 *   SKDiskImage attachWithParams:error:
 *   SKManager syncSharedManager / diskForPath:
 *   SKDisk isDiskImage
 *
 * The implementation is not the rejected 86530dd ENOTSUP substitute. Attach runs
 * /usr/bin/hdiutil in the guest, verifies the resulting mount, and records a real
 * SKDisk; detach runs hdiutil detach and removes that record.
 */

#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <sys/types.h>
#import <sys/mount.h>

extern void SKLog(const char *format, ...) __attribute__((format(printf, 1, 2)));
extern NSError *SKPOSIXError(int code);
extern NSError *SKErrorWithMessage(int code, NSString *message);
extern NSString *SKStringFromCString(const char *value);
extern NSString *SKHostPathForGuestMount(NSString *guestMount);

@interface SKMountParams : NSObject
{
	bool _readOnly;
	bool _noBrowse;
	bool _force;
	bool _recursive;
	bool _raidTraverse;
	NSURL *_mountPoint;
	NSSet *_allParams;
}
- (instancetype)initWithParams:(SKMountParams *)params;
- (bool)readOnly;
- (void)setReadOnly:(bool)value;
- (bool)noBrowse;
- (void)setNoBrowse:(bool)value;
- (bool)force;
- (void)setForce:(bool)value;
- (bool)recursive;
- (void)setRecursive:(bool)value;
- (bool)raidTraverse;
- (void)setRaidTraverse:(bool)value;
- (NSURL *)mountPoint;
- (void)setMountPoint:(NSURL *)mountPoint;
- (NSSet *)allParams;
- (void)setAllParams:(NSSet *)allParams;
@end

@interface SKDiskImageAttachParams : NSObject
{
	bool _readOnly;
	bool _stdinPassPhrase;
	bool _isManagedAttach;
	bool _is4KBlockSize;
	bool _emulateExternalDisk;
	long long _policy;
	SKMountParams *_mountParams;
}
- (instancetype)initWithParams:(SKMountParams *)params;
- (SKMountParams *)mountParams;
- (void)setMountParams:(SKMountParams *)mountParams;
- (bool)readOnly;
- (void)setReadOnly:(bool)value;
- (bool)stdinPassPhrase;
- (void)setStdinPassPhrase:(bool)value;
- (bool)isManagedAttach;
- (void)setIsManagedAttach:(bool)value;
- (bool)is4KBlockSize;
- (void)setIs4KBlockSize:(bool)value;
- (bool)emulateExternalDisk;
- (void)setEmulateExternalDisk:(bool)value;
- (long long)policy;
- (void)setPolicy:(long long)policy;
@end

@interface SKDisk : NSObject
{
	NSString *_diskIdentifier;
	NSString *_mountPoint;
	NSString *_volumeName;
	NSString *_filesystemType;
	NSString *_volumeUUID;
	bool _isDiskImage;
	bool _isNetwork;
	bool _isInternal;
	bool _isRemovable;
	bool _isWritable;
	unsigned long long _totalSpace;
	unsigned long long _freeSpace;
	unsigned long long _availableSpace;
}
- (instancetype)initWithMountPoint:(NSString *)mountPoint
	filesystemType:(NSString *)filesystemType
	readOnly:(bool)readOnly;
- (instancetype)initWithDevice:(NSString *)device
	mountPoint:(NSString *)mountPoint
	filesystemType:(NSString *)filesystemType
	readOnly:(bool)readOnly;
- (void)setTotalSpace:(unsigned long long)totalSpace
	freeSpace:(unsigned long long)freeSpace
	availableSpace:(unsigned long long)availableSpace;
- (char)isDiskImage;
- (NSString *)diskIdentifier;
- (NSString *)mountPoint;
- (NSString *)volumeName;
- (NSString *)filesystemType;
- (NSString *)volumeUUID;
- (bool)isNetwork;
- (bool)isInternal;
- (bool)isRemovable;
- (bool)isWritable;
- (unsigned long long)totalSpace;
- (unsigned long long)freeSpace;
- (unsigned long long)availableSpace;
@end

@interface SKBaseManager : NSObject
+ (instancetype)sharedManager;
@end

@interface SKManager : SKBaseManager
{
	NSMutableSet *_allDisks;
	NSMutableSet *_hostDisks;
	NSMutableSet *_attachedDisks;
}
+ (instancetype)syncSharedManager;
- (void)syncAllDisks;
- (void)addAttachedDisk:(SKDisk *)disk;
- (void)removeAttachedDisk:(SKDisk *)disk;
- (NSSet *)allDisksSet;
- (NSSet *)allDisks;
- (SKDisk *)diskForPath:(NSString *)path;
- (SKDisk *)_diskForPath:(NSString *)path isNetworkMount:(char *)isNetworkMount;
- (SKDisk *)diskForBSDname:(NSString *)name;
@end

@interface SKDiskImage : NSObject
{
	NSURL *_imageURL;
	NSArray *_shadowURLs;
	id _deviceHandle;
	id _diParams;
	NSString *_mountPoint;
	SKDisk *_mountedDisk;
}
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;
- (instancetype)initWithURL:(NSURL *)url diParams:(id)diParams shadowURLs:(NSArray *)shadowURLs error:(NSError **)error;
- (instancetype)initWithURL:(NSURL *)url diParams:(id)diParams error:(NSError **)error;
- (instancetype)initWithURL:(NSURL *)url shadowURLs:(NSArray *)shadowURLs error:(NSError **)error;
- (NSURL *)imageURL;
- (NSArray *)shadowURLs;
- (id)diParams;
- (void)setDiParams:(id)diParams;
- (id)deviceHandle;
- (void)setDeviceHandle:(id)deviceHandle;
- (char)isAttached;
- (NSString *)mountPoint;
- (id)attachWithParams:(SKDiskImageAttachParams *)params error:(NSError **)error;
- (id)attachWithError:(NSError **)error;
- (id)attachNoMountWithError:(NSError **)error;
- (id)diAttachWithParams:(SKDiskImageAttachParams *)params error:(NSError **)error;
- (char)mount:(NSURL *)mountPoint params:(SKMountParams *)params outError:(NSError **)error;
- (char)detachWithError:(NSError **)error;
- (char)ejectWithError:(NSError **)error;
@end
