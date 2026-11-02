// Declarations the AppKit Swift overlay needs, written for Darling from AppKit's public API documentation. The overlay
// imports this only when the SDK has no AppKit Clang module; with one it re-exports that instead. The functions are
// exported by Darling's AppKit.framework.
#ifndef DARLING_APPKIT_SHIMS_H
#define DARLING_APPKIT_SHIMS_H

#import <Foundation/Foundation.h>

// Where the SDK has AppKit's headers (without a module map), use them: cocotron declares every one of these six
// itself (NSGraphics.h, NSCell.h, AppKit.h), so redeclaring them is an ODR clash on the classes
// and an ambiguity on the enum and the functions, not a duplicate definition.
#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#else
// A named enum (like NS_ENUM) is imported as a nominal type and mangled `So22NSCompositingOperationV`, matching the
// symbols apps built against the macOS SDK import. An anonymous `typedef enum { } X` would mangle as a typealias.
typedef enum NSCompositingOperation : NSUInteger {
	NSCompositingOperationClear = 0,
	NSCompositingOperationCopy = 1,
	NSCompositingOperationSourceOver = 2,
} NSCompositingOperation;

@interface NSSound : NSObject
@end

@interface NSImage : NSObject
+ (nullable instancetype)imageNamed:(NSString *)name;
@end

void NSRectFillUsingOperation(NSRect rect, NSCompositingOperation operation);
void NSFrameRectWithWidthUsingOperation(NSRect rect, CGFloat frameWidth, NSCompositingOperation operation);
void NSBeep(void);
int NSApplicationMain(int argc, const char *argv[]);
#endif

#endif
