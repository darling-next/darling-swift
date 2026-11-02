// Declarations of Darling's OSLog.framework (darling src/frameworks/OSLog) that the OSLog Swift
// overlay wraps.  The SDK the overlays are built against has no Clang module for the framework (it is
// this tree's own), so the classes and the one method the overlay calls are declared here, exactly as
// overlays/UniformTypeIdentifiers/shims does for Darling's UTType.  The names are the framework's own,
// so the imported Swift types mangle as __C.OSLogStore / __C.OSLogEntry / __C.OSLogEnumeratorOptions /
// __C.OSLogPosition / __C.OSLogEnumerator, which is what the demanded symbol names.
#ifndef DARLING_OSLOG_SHIMS_H
#define DARLING_OSLOG_SHIMS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, OSLogEnumeratorOptions) {
	OSLogEnumeratorReverse = 0x01,
};

@interface OSLogEntry : NSObject
@end

@interface OSLogEntryLog : OSLogEntry
@end

@interface OSLogPosition : NSObject
@end

@interface OSLogEnumerator : NSEnumerator
@end

@interface OSLogStore : NSObject

- (nullable OSLogEnumerator *)entriesEnumeratorWithOptions:(OSLogEnumeratorOptions)options
                                                  position:(nullable OSLogPosition *)position
                                                 predicate:(nullable NSPredicate *)predicate
                                                     error:(NSError **)error
	NS_SWIFT_NAME(entriesEnumerator(with:position:predicate:));

@end

NS_ASSUME_NONNULL_END

#endif /* DARLING_OSLOG_SHIMS_H */
