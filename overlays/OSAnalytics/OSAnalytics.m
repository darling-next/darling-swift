/*
 * OSAnalytics.framework -- a TRUTHFUL substitute for Apple's private
 * /System/Library/PrivateFrameworks/OSAnalytics.framework.
 *
 * WHY IT EXISTS. This is the rung the batch was written for: the ladder stopped here.
 *
 *   Library not loaded: /System/Library/PrivateFrameworks/OSAnalytics.framework/Versions/A/OSAnalytics
 *   Referenced from: .../Xcode.app/Contents/SharedFrameworks/XCResultKit.framework/Versions/A/XCResultKit
 *
 * TWO referrers inside the load closure link it STRONGLY, and the demand is four names (measured per
 * dependency field of each referrer's own bind table, `llvm-objdump --macho --dyld-info`):
 *
 *   XCResultKit     _OBJC_CLASS_$_OSALegacyXform, _OSATransformOptionSymbolicate,
 *                   _OSATransformResultError, _OSATransformResultReport   (all 4)
 *   IDEFoundation   _OBJC_CLASS_$_OSALegacyXform                        (1)
 *
 * SHAPES. Apple's own stub --
 * <Xcode>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/
 * OSAnalytics.framework/Versions/A/OSAnalytics.tbd -- carries all four: the three _OSATransform*
 * names in its symbol list (so they are DATA, not functions) and `OSALegacyXform` in its
 * objc-classes list. WHAT THE CLIENT ASKS OF THE CLASS is read out of the clients themselves,
 * because the tbd says nothing about selectors:
 *
 *   XCResultKit  CrashReportUtilities.createHumanReadableCrashReport(from:destination:)
 *                builds [String: Any] = [OSATransformOptionSymbolicate: true], takes the class with
 *                _objc_opt_self, bridges the source URL to NSURL, and sends the CLASS method
 *                `transformURL:options:` with (NSURL, NSDictionary). It then reads the returned
 *                dictionary by `OSATransformResultReport` and, if the report is absent, by
 *                `OSATransformResultError`, whose value it casts with swift_dynamicCast to NSError.
 *   IDEFoundation the same class method with the same (NSURL, NSDictionary) shape -- its own
 *                selector string `transformURL:options:` is the one its code loads, and its error
 *                message for a failed transform is "An unknown error occurred transforming the
 *                crash report into a legacy, human-readable representation".
 *
 * WHAT IT ANSWERS, AND WHY THAT IS THE TRUTH. "OSAnalytics" is the crash/telemetry reporter. This
 * guest has none of it: no crash reporter daemon records anything, no report directory is
 * configured, no submission endpoint exists, and there is no legacy-report transformer. So:
 *
 *   transformURL:options:  returns a dictionary holding OSATransformResultError -- an NSError whose
 *                          description says the transform is not implemented here -- and NO
 *                          OSATransformResultReport, because no report could be produced. That is a
 *                          FACT turned into an explicit failure: XCResultKit sees the error object
 *                          it is written to expect and throws it, rather than receiving a fabricated
 *                          report. Nothing is configured, so nothing is reported and nothing is
 *                          claimed to have been reported.
 *   the three constants    option/result dictionary KEYS. Their values are this image's own
 *                          ("symbolicate", "report", "error"), and every reader of them goes
 *                          through these same symbols: XCResultKit passes the key it read from
 *                          OSATransformOptionSymbolicate and looks the result up by
 *                          OSATransformResultReport/OSATransformResultError, so the contract holds
 *                          end to end. Apple's literal values are not in any .tbd, are not written
 *                          anywhere the client reads them as text, and are NOT invented here as if
 *                          they were Apple's.
 *
 * NOT IMPLEMENTED, and deliberately named: the whole reporting surface (OSAReport, OSALog,
 * OSAStackShotReport, the -- in the tbd -- ~200 other symbols and 30 ObjC classes) is absent. The
 * four names above are the complete demand of the load closure; a client that binds more fails at
 * LOAD rather than calling something that answers wrongly. No "STUB:" string is printed: the error
 * is the truth, not a placeholder.
 */

#import <Foundation/Foundation.h>

/* The data symbols DVTPortal's sibling referrers bind. Apple's .tbd lists them in `symbols:`, so
 * they are data; their names say what they key. */
NSString *const OSATransformOptionSymbolicate = @"symbolicate";
NSString *const OSATransformResultReport = @"report";
NSString *const OSATransformResultError = @"error";

@interface OSALegacyXform : NSObject
@end

@implementation OSALegacyXform

/* The one method both measured clients send, in the shape both send it: a class method taking the
 * report URL and an options dictionary, answering a dictionary of results. */
+ (NSDictionary *)transformURL:(NSURL *)url options:(NSDictionary *)options
{
	(void)options; /* nothing configures the transform, so no option can change the answer */
	NSError *error = [NSError errorWithDomain:@"OSAnalytics"
					     code:1
					 userInfo:@{
		NSLocalizedDescriptionKey: @"The legacy crash report transform is not implemented in this "
					   @"guest (no OSAnalytics report machinery, no crash reporter, and no "
					   @"report configuration exist here). No report was produced.",
		NSURLErrorKey: url ?: [NSURL fileURLWithPath:@"/"],
	}];
	return @{ OSATransformResultError: error };
}

@end
