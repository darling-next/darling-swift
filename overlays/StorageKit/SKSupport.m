#import "SKInternal.h"

#include <stdarg.h>
#include <string.h>

/* Authoritative Darling guest-to-host path resolver, also used by hdiutil. */
extern int __darling_vchroot_expand(const char *path, char *out);

void SKLog(const char *format, ...)
{
	va_list ap;
	va_start(ap, format);
	fputs("StorageKitHdiutil: ", stderr);
	vfprintf(stderr, format, ap);
	fputc('\n', stderr);
	va_end(ap);
}

NSError *SKPOSIXError(int code)
{
	return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

NSError *SKErrorWithMessage(int code, NSString *message)
{
	NSDictionary *userInfo = nil;
	if (message != nil) {
		userInfo = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
	}
	return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:userInfo];
}

NSString *SKStringFromCString(const char *value)
{
	if (value == NULL || value[0] == '\0') {
		return nil;
	}
	return [NSString stringWithUTF8String:value];
}

NSString *SKHostPathForGuestMount(NSString *guestMount)
{
	if (guestMount == nil || [guestMount length] == 0) {
		return nil;
	}
	char hostPath[4096];
	memset(hostPath, 0, sizeof(hostPath));
	int result = __darling_vchroot_expand([guestMount fileSystemRepresentation], hostPath);
	if (result != 0 || hostPath[0] == '\0') {
		SKLog("vchroot expand failed for %s: rv=%d", [guestMount UTF8String], result);
		return nil;
	}
	return [NSString stringWithUTF8String:hostPath];
}
