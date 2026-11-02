/*
 * Guest smoke for the hdiutil-backed StorageKit provider.
 *
 * It exercises the measured CoreDevice call surface, not a guessed StorageKit API:
 * initWithURL:error:, SKDiskImageAttachParams init/setIsManagedAttach:/mountParams,
 * SKMountParams setReadOnly:/setNoBrowse:/setAllParams:/setMountPoint:,
 * attachWithParams:error:, SKManager syncSharedManager/diskForPath:,
 * SKDisk isDiskImage/mountPoint. It then reads the known .TrustCache file through
 * the returned mount, and detaches through the provider for owner cleanup.
 */

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

static int failures = 0;

static void sk_check(int condition, const char *what)
{
	if (condition) {
		printf("SK_CHECK=OK %s\n", what);
	} else {
		printf("SK_CHECK=FAIL %s\n", what);
		failures++;
	}
}

static unsigned char *readFileData(NSString *path, size_t *lengthOut)
{
	*lengthOut = 0;
	int fd = open([path fileSystemRepresentation], O_RDONLY);
	if (fd < 0) {
		printf("SK_READ_ERRNO=%d %s\n", errno, [path UTF8String]);
		return NULL;
	}
	size_t capacity = 4096;
	size_t total = 0;
	unsigned char *data = malloc(capacity);
	if (data == NULL) {
		close(fd);
		return NULL;
	}
	for (;;) {
		if (total == capacity) {
			size_t grown = capacity * 2;
			unsigned char *next = realloc(data, grown);
			if (next == NULL) {
				free(data);
				close(fd);
				printf("SK_READ_ALLOC_FAILED=%lu\n", (unsigned long)total);
				return NULL;
			}
			data = next;
			capacity = grown;
		}
		ssize_t count = read(fd, data + total, capacity - total);
		if (count > 0) {
			total += (size_t)count;
			continue;
		}
		if (count < 0 && errno == EINTR) {
			continue;
		}
		if (count < 0) {
			printf("SK_READ_ERRNO=%d %s\n", errno, [path UTF8String]);
			free(data);
			close(fd);
			return NULL;
		}
		break;
	}
	close(fd);
	*lengthOut = total;
	return data;
}

/*
 * Run the actual guest /usr/bin/cmp on two paths. No hash implementation is
 * substituted here: a loader failure is reported from the child's output and
 * only then may the explicit C byte-compare fallback run.
 */
static int runCmp(NSString *left, NSString *right, int *spawnErrorOut, NSString **outputOut)
{
	if (spawnErrorOut != NULL) {
		*spawnErrorOut = 0;
	}
	if (outputOut != NULL) {
		*outputOut = nil;
	}
	char temporary[] = "/tmp/storagekit-cmp-XXXXXX";
	int fd = mkstemp(temporary);
	if (fd < 0) {
		if (spawnErrorOut != NULL) {
			*spawnErrorOut = errno;
		}
		return 127;
	}
	close(fd);

	char *arguments[] = {
		(char *)"/usr/bin/cmp",
		(char *)"-s",
		(char *)[left fileSystemRepresentation],
		(char *)[right fileSystemRepresentation],
		NULL
	};

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
		spawnError = posix_spawn(&pid, "/usr/bin/cmp", &actions, NULL, arguments, environ);
	}
	posix_spawn_file_actions_destroy(&actions);

	if (actionError != 0 || spawnError != 0) {
		if (spawnErrorOut != NULL) {
			*spawnErrorOut = actionError != 0 ? actionError : spawnError;
		}
		unlink(temporary);
		return 127;
	}

	int waitStatus = 0;
	while (waitpid(pid, &waitStatus, 0) < 0) {
		if (errno != EINTR) {
			break;
		}
	}
	int status = WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : 128 + WTERMSIG(waitStatus);
	NSString *output = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:temporary]
		encoding:NSUTF8StringEncoding
		error:NULL];
	unlink(temporary);
	if (outputOut != NULL) {
		*outputOut = output;
	}
	return status;
}

static bool cmpOutputIsLoaderFailure(int spawnError, NSString *output)
{
	if (spawnError != 0) {
		return true;
	}
	if (output == nil) {
		return false;
	}
	return [output rangeOfString:@"Library not loaded"].location != NSNotFound ||
		[output rangeOfString:@"Symbol not found"].location != NSNotFound ||
		[output rangeOfString:@"image not found"].location != NSNotFound ||
		[output rangeOfString:@"dyld: "].location != NSNotFound;
}

int main(int argc, char **argv)
{
	NSString *imagePath = argc > 1
		? [NSString stringWithUTF8String:argv[1]]
		: @"/Volumes/SystemRoot/home/ilyagulya/work/local-target/xcode-26.3/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/16.4/DeveloperDiskImage.dmg";
	NSString *mountPoint = argc > 2
		? [NSString stringWithUTF8String:argv[2]]
		: @"/Volumes/sk-storagekit-test";
	NSString *expectedPath = argc > 3
		? [NSString stringWithUTF8String:argv[3]]
		: @"/Volumes/SystemRoot/home/ilyagulya/work/wr-fresh/darling-workspace/evidence/storagekit-hdiutil-provider-20261025/expected.TrustCache";
	NSString *corruptPath = argc > 4
		? [NSString stringWithUTF8String:argv[4]]
		: @"/Volumes/SystemRoot/home/ilyagulya/work/wr-fresh/darling-workspace/evidence/storagekit-hdiutil-provider-20261025/expected-corrupt-1byte.TrustCache";

	@autoreleasepool {
		NSError *error = nil;
		SKManager *manager = [SKManager syncSharedManager];
		sk_check(manager != nil, "manager");
		SKDisk *root = [manager diskForPath:@"/"];
		printf("SK_ROOT_MOUNT=%s\n", root != nil ? [[root mountPoint] UTF8String] : "(nil)");
		sk_check(root != nil && [root isDiskImage] == 0, "host-mount-not-image");

		NSURL *url = [NSURL fileURLWithPath:imagePath];
		SKDiskImage *image = [[SKDiskImage alloc] initWithURL:url error:&error];
		sk_check(image != nil, "image-init");

		SKDiskImageAttachParams *params = [[SKDiskImageAttachParams alloc] init];
		SKMountParams *mountParams = [params mountParams];
		sk_check(mountParams != nil, "mount-params");
		[params setIsManagedAttach:YES];
		[mountParams setReadOnly:YES];
		[mountParams setNoBrowse:YES];
		[mountParams setAllParams:[NSSet setWithObject:@"storagekit-smoke"]];
		[mountParams setMountPoint:[NSURL fileURLWithPath:mountPoint]];

		error = nil;
		SKDisk *disk = [image attachWithParams:params error:&error];
		if (disk == nil) {
			printf("SK_ATTACH_ERROR=%ld %s\n", (long)[error code],
				error != nil ? [[error description] UTF8String] : "(no error)");
		}
		sk_check(disk != nil, "attach");
		if (disk != nil) {
			sk_check([disk isDiskImage] == 1, "attached-is-disk-image");
			sk_check([[disk mountPoint] isEqualToString:mountPoint], "attached-mount-point");
			printf("SK_MOUNT=%s\n", [[disk mountPoint] UTF8String]);
			printf("SK_FSTYPE=%s\n", [[disk filesystemType] UTF8String]);
		}

		manager = [SKManager syncSharedManager];
		SKDisk *found = [manager diskForPath:mountPoint];
		sk_check(found != nil, "manager-disk");
		sk_check(found != nil && [found isDiskImage] == 1, "manager-is-disk-image");
		sk_check(found != nil && [[found mountPoint] isEqualToString:mountPoint], "manager-mount-point");

		NSString *knownFile = [mountPoint stringByAppendingPathComponent:@".TrustCache"];
		int goodSpawn = 0;
		int badSpawn = 0;
		NSString *goodOutput = nil;
		NSString *badOutput = nil;
		int goodRc = runCmp(knownFile, expectedPath, &goodSpawn, &goodOutput);
		int badRc = runCmp(knownFile, corruptPath, &badSpawn, &badOutput);
		printf("SK_CMP_GOOD_RC=%d\n", goodRc);
		printf("SK_CMP_BAD_RC=%d\n", badRc);
		if ([goodOutput length] > 0) {
			printf("SK_CMP_GOOD_OUT=%s\n", [goodOutput UTF8String]);
		}
		if ([badOutput length] > 0) {
			printf("SK_CMP_BAD_OUT=%s\n", [badOutput UTF8String]);
		}

		BOOL cmpLoaderFailed = cmpOutputIsLoaderFailure(goodSpawn, goodOutput) ||
			cmpOutputIsLoaderFailure(badSpawn, badOutput);
		BOOL contentOracle = NO;
		if (!cmpLoaderFailed) {
			contentOracle = goodRc == 0 && badRc == 1;
		} else {
			/*
			 * The actual guest cmp did not run. Record its concrete loader
			 * output above, then use the explicit in-process byte compare as a
			 * fallback. A cmp exit 1 for the good reference is a content result,
			 * not a loader failure, and does not enter this branch.
			 */
			printf("SK_CMP_LOADER_ERROR=1\n");
			printf("SK_CMP_FALLBACK=BYTE_COMPARE\n");
			size_t mountedBytes = 0;
			size_t expectedBytes = 0;
			size_t corruptBytes = 0;
			unsigned char *mountedData = readFileData(knownFile, &mountedBytes);
			unsigned char *expectedData = readFileData(expectedPath, &expectedBytes);
			unsigned char *corruptData = readFileData(corruptPath, &corruptBytes);
			contentOracle = mountedData != NULL && expectedData != NULL && corruptData != NULL &&
				mountedBytes == expectedBytes && expectedBytes == corruptBytes &&
				memcmp(mountedData, expectedData, expectedBytes) == 0 &&
				memcmp(mountedData, corruptData, corruptBytes) != 0;
			free(mountedData);
			free(expectedData);
			free(corruptData);
		}
		printf("SK_COMPARE=%s\n", contentOracle ? "OK" : "FAIL");
		sk_check(contentOracle, "cmp-byte-compare");

		/*
		 * Busy-detach negative control: keep a real descriptor on the mounted
		 * file. A successful detach here would be a false green; the provider
		 * and hdiutil must reject it and preserve the live manager record.
		 */
		int heldFd = open([knownFile fileSystemRepresentation], O_RDONLY);
		sk_check(heldFd >= 0, "busy-fd-open");
		error = nil;
		BOOL busyDetached = [image detachWithError:&error];
		printf("SK_BUSY_DETACH=%s\n", busyDetached ? "ACCEPTED" : "REJECTED");
		printf("SK_BUSY_ERROR_DOMAIN=%s\n",
			error != nil ? [[error domain] UTF8String] : "(nil)");
		printf("SK_BUSY_ERROR_CODE=%ld\n", error != nil ? (long)[error code] : -1L);
		printf("SK_BUSY_ERROR_DESC=%s\n",
			error != nil ? [[error description] UTF8String] : "(nil)");
		sk_check(!busyDetached && error != nil, "busy-detach-rejected");
		manager = [SKManager syncSharedManager];
		SKDisk *stillAttached = [manager diskForPath:mountPoint];
		sk_check(stillAttached != nil && [stillAttached isDiskImage] == 1,
			"busy-detach-retains-registration");
		sk_check(access([knownFile fileSystemRepresentation], R_OK) == 0,
			"busy-detach-mount-still-readable");
		if (heldFd >= 0) {
			close(heldFd);
		}

		error = nil;
		BOOL detached = [image detachWithError:&error];
		if (!detached) {
			printf("SK_DETACH_ERROR=%ld %s\n", (long)[error code],
				error != nil ? [[error description] UTF8String] : "(no error)");
		}
		sk_check(detached, "detach");
		printf("SK_DETACH=%s\n", detached ? "OK" : "FAIL");

		manager = [SKManager syncSharedManager];
		SKDisk *after = [manager diskForPath:mountPoint];
		sk_check(after == nil, "manager-cleared");
		sk_check(access([mountPoint fileSystemRepresentation], F_OK) != 0, "mountpoint-gone");

		/*
		 * Lifetime control: deallocating the image is not a detach. The real
		 * manager registration and mount must remain until an actual detach.
		 */
		NSString *lifetimeMountPoint = [mountPoint stringByAppendingString:@"-lifetime"];
		SKDiskImage *lifetimeImage = [[SKDiskImage alloc] initWithURL:url error:NULL];
		SKDiskImageAttachParams *lifetimeParams = [[SKDiskImageAttachParams alloc] init];
		[[lifetimeParams mountParams] setReadOnly:YES];
		[[lifetimeParams mountParams] setMountPoint:[NSURL fileURLWithPath:lifetimeMountPoint]];
		error = nil;
		SKDisk *lifetimeDisk = [lifetimeImage attachWithParams:lifetimeParams error:&error];
		sk_check(lifetimeDisk != nil, "lifetime-attach");
		[lifetimeImage release];
		manager = [SKManager syncSharedManager];
		SKDisk *lifetimeLive = [manager diskForPath:lifetimeMountPoint];
		sk_check(lifetimeLive != nil && [lifetimeLive isDiskImage] == 1,
			"dealloc-retains-registration");
		NSString *lifetimeFile = [lifetimeMountPoint stringByAppendingPathComponent:@".TrustCache"];
		sk_check(access([lifetimeFile fileSystemRepresentation], R_OK) == 0,
			"dealloc-mount-still-live");
		NSString *detachCommand = [NSString stringWithFormat:@"/usr/bin/hdiutil detach %@", lifetimeMountPoint];
		int cleanupStatus = system([detachCommand UTF8String]);
		sk_check(cleanupStatus == 0, "lifetime-cleanup-detach");
		sk_check(access([lifetimeMountPoint fileSystemRepresentation], F_OK) != 0,
			"lifetime-mountpoint-gone");
		manager = [SKManager syncSharedManager];
		SKDisk *lifetimeAfterExternal = [manager diskForPath:lifetimeMountPoint];
		sk_check(lifetimeAfterExternal == nil, "external-detach-manager-cleared");
		[lifetimeParams release];

		/*
		 * Cleanup-error control: the unmount is real, but rmdir cannot remove
		 * the directory because its parent is not writable. Detach must still
		 * succeed and clear the manager; the directory is not recursively
		 * deleted and must remain for the owner to inspect/remove.
		 */
		NSString *cleanupParent = @"/Volumes/sk-state-red-cleanup-parent";
		NSString *cleanupMountPoint = [cleanupParent stringByAppendingPathComponent:@"target"];
		const char *cleanupParentPath = [cleanupParent fileSystemRepresentation];
		const char *cleanupMountPath = [cleanupMountPoint fileSystemRepresentation];
		rmdir(cleanupMountPath);
		rmdir(cleanupParentPath);
		sk_check(mkdir(cleanupParentPath, 0755) == 0, "cleanup-parent-mkdir");
		sk_check(mkdir(cleanupMountPath, 0755) == 0, "cleanup-mountdir-mkdir");
		chmod(cleanupParentPath, 0755);

		SKDiskImage *cleanupImage = [[SKDiskImage alloc] initWithURL:url error:NULL];
		SKDiskImageAttachParams *cleanupParams = [[SKDiskImageAttachParams alloc] init];
		[[cleanupParams mountParams] setReadOnly:YES];
		[[cleanupParams mountParams] setMountPoint:[NSURL fileURLWithPath:cleanupMountPoint]];
		error = nil;
		SKDisk *cleanupDisk = [cleanupImage attachWithParams:cleanupParams error:&error];
		sk_check(cleanupDisk != nil, "cleanup-error-attach");
		sk_check(chmod(cleanupParentPath, 0555) == 0, "cleanup-parent-readonly");

		error = nil;
		BOOL cleanupDetached = [cleanupImage detachWithError:&error];
		printf("SK_CLEANUP_DETACH=%s\n", cleanupDetached ? "OK" : "FAIL");
		sk_check(cleanupDetached, "cleanup-error-detach-success");
		manager = [SKManager syncSharedManager];
		SKDisk *cleanupAfter = [manager diskForPath:cleanupMountPoint];
		sk_check(cleanupAfter == nil, "cleanup-error-manager-cleared");
		sk_check(access(cleanupMountPath, F_OK) == 0, "cleanup-error-mountdir-retained");

		chmod(cleanupParentPath, 0755);
		rmdir(cleanupMountPath);
		rmdir(cleanupParentPath);
		[cleanupParams release];
		[cleanupImage release];

		/*
		 * Mount-identity control: A is /Volumes/sk; B is
		 * /Volumes/peer/Volumes/sk. A suffix comparison would mistake A's
		 * host path for B's and retain A after an external detach.
		 */
		const char *identityParent = "/Volumes/peer";
		const char *identityPeer = "/Volumes/peer/Volumes";
		const char *identityA = "/Volumes/sk";
		const char *identityB = "/Volumes/peer/Volumes/sk";
		rmdir(identityB);
		rmdir(identityPeer);
		rmdir(identityParent);
		rmdir(identityA);
		sk_check(mkdir(identityA, 0755) == 0, "identity-a-mkdir");
		sk_check(mkdir(identityParent, 0755) == 0, "identity-peer-mkdir");
		sk_check(mkdir(identityPeer, 0755) == 0, "identity-peer-volumes-mkdir");
		sk_check(mkdir(identityB, 0755) == 0, "identity-b-mkdir");

		SKDiskImageAttachParams *identityAParams = [[SKDiskImageAttachParams alloc] init];
		[[identityAParams mountParams] setReadOnly:YES];
		[[identityAParams mountParams] setMountPoint:[NSURL fileURLWithPath:[NSString stringWithUTF8String:identityA]]];
		SKDiskImage *identityImageA = [[SKDiskImage alloc] initWithURL:url error:NULL];
		error = nil;
		id identityDiskA = [identityImageA attachWithParams:identityAParams error:&error];
		sk_check(identityDiskA != nil, "identity-a-attach");

		SKDiskImageAttachParams *identityBParams = [[SKDiskImageAttachParams alloc] init];
		[[identityBParams mountParams] setReadOnly:YES];
		[[identityBParams mountParams] setMountPoint:[NSURL fileURLWithPath:[NSString stringWithUTF8String:identityB]]];
		SKDiskImage *identityImageB = [[SKDiskImage alloc] initWithURL:url error:NULL];
		error = nil;
		id identityDiskB = [identityImageB attachWithParams:identityBParams error:&error];
		sk_check(identityDiskB != nil, "identity-b-attach");

		int identityDetachStatus = system("/usr/bin/hdiutil detach /Volumes/sk");
		sk_check(identityDetachStatus == 0, "identity-a-external-detach");
		manager = [SKManager syncSharedManager];
		SKDisk *identityAAfter = [manager diskForPath:@"/Volumes/sk"];
		SKDisk *identityBAfter = [manager diskForPath:@"/Volumes/peer/Volumes/sk"];
		sk_check(identityAAfter == nil, "identity-a-not-retained");
		sk_check(identityBAfter != nil && [identityBAfter isDiskImage] == 1,
			"identity-b-still-live");
		NSString *identityBFile = @"/Volumes/peer/Volumes/sk/.TrustCache";
		sk_check(access([identityBFile fileSystemRepresentation], R_OK) == 0,
			"identity-b-still-readable");

		error = nil;
		sk_check([identityImageB detachWithError:&error], "identity-b-cleanup-detach");
		[identityBParams release];
		[identityImageB release];
		[identityAParams release];
		[identityImageA release];
		rmdir(identityB);
		rmdir(identityPeer);
		rmdir(identityParent);
		rmdir(identityA);

		error = nil;
		id nilResult = [image attachWithParams:nil error:&error];
		sk_check(nilResult == nil && [error code] == EINVAL, "nil-params-einval");

		NSURL *missingURL = [NSURL fileURLWithPath:[imagePath stringByAppendingString:@".missing"]];
		SKDiskImage *missingImage = [[SKDiskImage alloc] initWithURL:missingURL error:NULL];
		SKDiskImageAttachParams *missingParams = [[SKDiskImageAttachParams alloc] init];
		[[missingParams mountParams] setMountPoint:[NSURL fileURLWithPath:[mountPoint stringByAppendingString:@"-missing"]]];
		error = nil;
		id missingResult = [missingImage attachWithParams:missingParams error:&error];
		sk_check(missingResult == nil && [error code] == ENOENT, "missing-image-enoent");
		[missingParams release];
		[missingImage release];

		[params release];
		[image release];
	}
	printf("SK_FAILURES=%d\n", failures);
	if (failures == 0) {
		printf("SK_SMOKE=OK\n");
	}
	return failures == 0 ? 0 : 1;
}
