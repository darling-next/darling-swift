#import "SKInternal.h"

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static void SKStoreError(NSError **slot, NSError *error)
{
	if (slot != NULL) {
		*slot = error;
	}
}

static NSString *SKPathFromMountURL(NSURL *url)
{
	if (url == nil) {
		return nil;
	}
	if (![url isKindOfClass:[NSURL class]]) {
		return nil;
	}
	NSString *path = [url path];
	if (path == nil || [path length] == 0) {
		return nil;
	}
	return [path stringByStandardizingPath];
}

static NSString *SKTrimmedLine(NSString *line)
{
	return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *SKParseMountPointFromOutput(NSString *output)
{
	NSString *result = nil;
	for (NSString *rawLine in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
		NSString *line = SKTrimmedLine(rawLine);
		if ([line length] == 0 || ![line hasPrefix:@"/"]) {
			continue;
		}
		if ([line hasPrefix:@"/dev/"]) {
			continue;
		}
		result = line;
	}
	return result;
}

static NSString *SKUnescapeMountPath(NSString *field)
{
	if (field == nil || [field rangeOfString:@"\\"].location == NSNotFound) {
		return field;
	}
	NSMutableString *result = [NSMutableString stringWithCapacity:[field length]];
	NSUInteger length = [field length];
	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [field characterAtIndex:i];
		if (c == '\\' && i + 3 < length) {
			unichar d0 = [field characterAtIndex:i + 1];
			unichar d1 = [field characterAtIndex:i + 2];
			unichar d2 = [field characterAtIndex:i + 3];
			if (d0 >= '0' && d0 <= '7' && d1 >= '0' && d1 <= '7' && d2 >= '0' && d2 <= '7') {
				[result appendFormat:@"%C", (unichar)((d0 - '0') * 64 + (d1 - '0') * 8 + (d2 - '0'))];
				i += 3;
				continue;
			}
		}
		[result appendFormat:@"%C", c];
	}
	return result;
}

/*
 * The guest mount point is inside the prefix, so the host mount table's mount
 * field is "<prefix><guest mount point>".  Read the kernel's real mount table
 * through the SystemRoot view; this distinguishes a mounted FUSE root from a
 * directory that hdiutil has merely created.
 */
static int SKHostMountTableMountState(NSString *guestMountPoint)
{
	if (guestMountPoint == nil || [guestMountPoint length] == 0) {
		return -1;
	}
	NSString *hostGuestMount = SKHostPathForGuestMount(guestMountPoint);
	if (hostGuestMount == nil) {
		return -1;
	}
	NSString *contents = [NSString stringWithContentsOfFile:@"/Volumes/SystemRoot/proc/self/mounts"
		encoding:NSUTF8StringEncoding
		error:NULL];
	if (contents == nil) {
		return -1;
	}
	for (NSString *line in [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
		NSArray *fields = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSMutableArray *nonEmpty = [NSMutableArray arrayWithCapacity:6];
		for (NSString *field in fields) {
			if ([field length] > 0) {
				[nonEmpty addObject:field];
			}
		}
		if ([nonEmpty count] < 2) {
			continue;
		}
		NSString *hostMount = SKUnescapeMountPath([nonEmpty objectAtIndex:1]);
		if ([hostMount isEqualToString:hostGuestMount]) {
			return 1;
		}
	}
	return 0;
}

static bool SKHostMountTableHasMount(NSString *guestMountPoint)
{
	return SKHostMountTableMountState(guestMountPoint) == 1;
}

/*
 * Run hdiutil in the guest. stdout and stderr go to one private temporary file: the
 * provider must not inherit a caller's pipe (a short-lived child writing a pipe whose
 * reader is not draining can convert a mount failure into an apparent hang).
 */
static int SKRunHdiutil(NSArray *arguments, NSString **output, NSError **error)
{
	char temporary[] = "/tmp/storagekit-hdiutil-XXXXXX";
	int fd = mkstemp(temporary);
	if (fd < 0) {
		SKStoreError(error, SKPOSIXError(errno));
		return -1;
	}
	close(fd);

	NSUInteger argumentCount = [arguments count];
	char **argv = calloc(argumentCount + 2, sizeof(char *));
	if (argv == NULL) {
		unlink(temporary);
		SKStoreError(error, SKPOSIXError(ENOMEM));
		return -1;
	}
	argv[0] = (char *)"/usr/bin/hdiutil";
	for (NSUInteger i = 0; i < argumentCount; i++) {
		argv[i + 1] = (char *)[[arguments objectAtIndex:i] fileSystemRepresentation];
	}
	argv[argumentCount + 1] = NULL;

	posix_spawn_file_actions_t actions;
	int actionError = posix_spawn_file_actions_init(&actions);
	if (actionError == 0) {
		actionError = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
	}
	if (actionError == 0) {
		actionError = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, temporary,
			O_WRONLY | O_CREAT | O_TRUNC, 0600);
	}
	if (actionError == 0) {
		actionError = posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
	}

	pid_t pid = 0;
	int spawnError = -1;
	if (actionError == 0) {
		spawnError = posix_spawn(&pid, "/usr/bin/hdiutil", &actions, NULL, argv, environ);
	}
	posix_spawn_file_actions_destroy(&actions);
	free(argv);

	if (actionError != 0 || spawnError != 0) {
		int code = actionError != 0 ? actionError : spawnError;
		unlink(temporary);
		SKStoreError(error, SKPOSIXError(code));
		return -1;
	}

	int waitStatus = 0;
	while (waitpid(pid, &waitStatus, 0) < 0) {
		if (errno != EINTR) {
			break;
		}
	}

	int status = 128;
	if (WIFEXITED(waitStatus)) {
		status = WEXITSTATUS(waitStatus);
	} else if (WIFSIGNALED(waitStatus)) {
		status = 128 + WTERMSIG(waitStatus);
	}

	NSString *collected = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:temporary]
		encoding:NSUTF8StringEncoding
		error:NULL];
	unlink(temporary);
	if (output != NULL) {
		*output = collected != nil ? collected : @"";
	}
	return status;
}

static NSError *SKHdiutilFailure(NSString *action, int status, NSString *output)
{
	NSString *detail = output != nil ? SKTrimmedLine(output) : @"";
	NSString *message = [NSString stringWithFormat:@"hdiutil %@ failed with status %d%@%@",
		action, status, [detail length] > 0 ? @": " : @"", detail];
	int code = EIO;
	if ([detail rangeOfString:@"No such file" options:NSCaseInsensitiveSearch].location != NSNotFound) {
		code = ENOENT;
	}
	return SKErrorWithMessage(code, message);
}

static bool SKWaitForMount(NSString *mountPoint, NSTimeInterval timeout)
{
	if (mountPoint == nil) {
		return false;
	}
	NSUInteger attempts = (NSUInteger)(timeout / 0.05);
	if (attempts < 1) {
		attempts = 1;
	}
	for (NSUInteger i = 0; i < attempts; i++) {
		const char *path = [mountPoint fileSystemRepresentation];
		struct statfs fs;
		if (statfs(path, &fs) == 0 && (fs.f_blocks > 0 || fs.f_fstypename[0] != '\0')) {
			return true;
		}
		/*
		 * Guest statfs is not implemented for every FUSE mount. The host
		 * mount table is the kernel state that distinguishes a mounted FUSE
		 * root from the empty directory hdiutil creates first.
		 */
		if (SKHostMountTableHasMount(mountPoint)) {
			return true;
		}
		usleep(50000);
	}
	return false;
}

@implementation SKDiskImage

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error
{
	return [self initWithURL:url diParams:nil shadowURLs:nil error:error];
}

- (instancetype)initWithURL:(NSURL *)url diParams:(id)diParams error:(NSError **)error
{
	return [self initWithURL:url diParams:diParams shadowURLs:nil error:error];
}

- (instancetype)initWithURL:(NSURL *)url shadowURLs:(NSArray *)shadowURLs error:(NSError **)error
{
	return [self initWithURL:url diParams:nil shadowURLs:shadowURLs error:error];
}

- (instancetype)initWithURL:(NSURL *)url
	diParams:(id)diParams
	shadowURLs:(NSArray *)shadowURLs
	error:(NSError **)error
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_imageURL = [url retain];
	_shadowURLs = [shadowURLs retain];
	_diParams = [diParams retain];
	_deviceHandle = nil;
	_mountPoint = nil;
	_mountedDisk = nil;
	SKStoreError(error, nil);
	return self;
}

- (void)dealloc
{
	/*
	 * Deallocation is not a detach. If the image still has a live mount, the
	 * manager's real registration must outlive this object until an actual
	 * successful detach removes it.
	 */
	if (_mountedDisk != nil) {
		SKLog("image deallocated with live mount %s; registration retained",
			[_mountPoint UTF8String]);
	}
	[_imageURL release];
	[_shadowURLs release];
	[_diParams release];
	[_deviceHandle release];
	[_mountPoint release];
	[_mountedDisk release];
	[super dealloc];
}

- (NSURL *)imageURL
{
	return _imageURL;
}

- (NSArray *)shadowURLs
{
	return _shadowURLs;
}

- (id)diParams
{
	return _diParams;
}

- (void)setDiParams:(id)diParams
{
	if (_diParams == diParams) {
		return;
	}
	[diParams retain];
	[_diParams release];
	_diParams = diParams;
}

- (id)deviceHandle
{
	return _deviceHandle;
}

- (void)setDeviceHandle:(id)deviceHandle
{
	if (_deviceHandle == deviceHandle) {
		return;
	}
	[deviceHandle retain];
	[_deviceHandle release];
	_deviceHandle = deviceHandle;
}

- (char)isAttached
{
	return _mountedDisk != nil ? 1 : 0;
}

- (NSString *)mountPoint
{
	return _mountPoint;
}

- (id)attachWithParams:(SKDiskImageAttachParams *)params error:(NSError **)error
{
	SKLog("attachWithParams: url=%s params=%s",
		_imageURL != nil ? [[_imageURL path] UTF8String] : "(nil)",
		params != nil ? "present" : "nil");

	SKStoreError(error, nil);
	if (params == nil) {
		SKStoreError(error, SKPOSIXError(EINVAL));
		return nil;
	}
	if (_imageURL == nil) {
		SKStoreError(error, SKPOSIXError(EINVAL));
		return nil;
	}

	NSString *imagePath = [_imageURL path];
	if (imagePath == nil || ![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
		SKStoreError(error, SKPOSIXError(ENOENT));
		return nil;
	}

	if (_mountedDisk != nil) {
		return _mountedDisk;
	}

	SKMountParams *mountParams = [params mountParams];
	NSURL *mountURL = mountParams != nil ? [mountParams mountPoint] : nil;
	NSString *mountPoint = SKPathFromMountURL(mountURL);
	if (mountURL != nil && mountPoint == nil) {
		SKStoreError(error, SKPOSIXError(EINVAL));
		return nil;
	}
	bool readOnly = [params readOnly] || (mountParams != nil && [mountParams readOnly]);

	NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"attach"];
	if (mountPoint != nil) {
		[arguments addObject:@"-mountpoint"];
		[arguments addObject:mountPoint];
	}
	if (readOnly) {
		[arguments addObject:@"-readonly"];
	}
	[arguments addObject:imagePath];

	SKLog("hdiutil attach image=%s mount=%s readonly=%d", [imagePath UTF8String],
		mountPoint != nil ? [mountPoint UTF8String] : "(default)", readOnly ? 1 : 0);

	NSString *output = nil;
	int status = SKRunHdiutil(arguments, &output, error);
	SKLog("hdiutil attach status=%d output=%s", status,
		output != nil ? [SKTrimmedLine(output) UTF8String] : "(nil)");
	if (status < 0) {
		return nil;
	}
	if (status != 0) {
		SKStoreError(error, SKHdiutilFailure(@"attach", status, output));
		return nil;
	}

	if (mountPoint == nil) {
		NSString *parsed = SKParseMountPointFromOutput(output);
		if ([parsed length] > 0) {
			mountPoint = [parsed stringByStandardizingPath];
		}
	}
	if (mountPoint == nil) {
		SKStoreError(error, SKErrorWithMessage(EIO,
			[NSString stringWithFormat:@"hdiutil attach returned no mount point: %@", output]));
		return nil;
	}

	if (!SKWaitForMount(mountPoint, 5.0)) {
		NSMutableArray *detachArguments = [NSMutableArray arrayWithObjects:@"detach", mountPoint, nil];
		NSString *detachOutput = nil;
		(void)SKRunHdiutil(detachArguments, &detachOutput, NULL);
		SKStoreError(error, SKErrorWithMessage(EIO,
			[NSString stringWithFormat:@"hdiutil reported success but %@ is not mounted", mountPoint]));
		return nil;
	}

	SKDisk *disk = [[SKDisk alloc] initWithMountPoint:mountPoint filesystemType:nil readOnly:readOnly];
	[[SKManager sharedManager] addAttachedDisk:disk];
	_mountPoint = [mountPoint copy];
	_mountedDisk = [disk retain];
	SKLog("attach complete: mount=%s disk=%s", [mountPoint UTF8String], [[disk description] UTF8String]);
	return [disk autorelease];
}

- (id)attachWithError:(NSError **)error
{
	SKDiskImageAttachParams *params = [[SKDiskImageAttachParams alloc] init];
	id result = [self attachWithParams:params error:error];
	[params release];
	return result;
}

- (id)attachNoMountWithError:(NSError **)error
{
	/*
	 * hdiutil's real attach operation mounts. There is no separate no-mount primitive
	 * in this runtime; return the genuine attach result rather than a synthetic handle.
	 */
	return [self attachWithError:error];
}

- (id)diAttachWithParams:(SKDiskImageAttachParams *)params error:(NSError **)error
{
	/*
	 * The measured native contract performs diAttach and mount; the consumer calls
	 * attachWithParams:. Keep this entry point real (mounted) rather than returning
	 * a handle that no mounted disk backs.
	 */
	return [self attachWithParams:params error:error];
}

- (char)mount:(NSURL *)mountPoint params:(SKMountParams *)params outError:(NSError **)error
{
	if (_mountedDisk != nil) {
		return 1;
	}
	SKDiskImageAttachParams *attachParams = [[SKDiskImageAttachParams alloc] init];
	if (params != nil) {
		[attachParams setMountParams:params];
	}
	if (mountPoint != nil) {
		[[attachParams mountParams] setMountPoint:mountPoint];
	}
	id disk = [self attachWithParams:attachParams error:error];
	[attachParams release];
	return disk != nil ? 1 : 0;
}

- (char)detachWithError:(NSError **)error
{
	SKStoreError(error, nil);
	if (_mountPoint == nil || _mountedDisk == nil) {
		return 1;
	}

	NSArray *arguments = [NSArray arrayWithObjects:@"detach", _mountPoint, nil];
	NSString *output = nil;
	int status = SKRunHdiutil(arguments, &output, error);
	if (status < 0) {
		return 0;
	}
	if (status != 0) {
		SKStoreError(error, SKHdiutilFailure(@"detach", status, output));
		return 0;
	}

	int mountState = SKHostMountTableMountState(_mountPoint);
	if (mountState != 0) {
		SKStoreError(error, SKErrorWithMessage(mountState > 0 ? EBUSY : EIO,
			mountState > 0
				? [NSString stringWithFormat:@"hdiutil detach returned success but %@ is still mounted", _mountPoint]
				: [NSString stringWithFormat:@"cannot confirm that %@ was unmounted", _mountPoint]));
		return 0;
	}

	[[SKManager sharedManager] removeAttachedDisk:_mountedDisk];
	[_mountedDisk release];
	_mountedDisk = nil;
	[_mountPoint release];
	_mountPoint = nil;
	return 1;
}

- (char)ejectWithError:(NSError **)error
{
	return [self detachWithError:error];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<SKDiskImage url=%@ attached=%d mount=%@>",
		_imageURL, (int)[self isAttached], _mountPoint];
}

@end
