/*
 * libCoreEntitlements.dylib -- a TRUTHFUL substitute for Apple's /usr/lib/libCoreEntitlements.dylib.
 *
 * WHY IT EXISTS. The Xcode 26.3 load-time ladder reaches this image through DVTPortal: the guest
 * reports
 *
 *   Library not loaded: /usr/lib/libCoreEntitlements.dylib
 *   Referenced from: .../Xcode.app/Contents/SharedFrameworks/DVTPortal.framework/Versions/A/DVTPortal
 *
 * and DVTPortal binds SIX names from the dependency field `libCoreEntitlements`, all EAGERLY in
 * __DATA_CONST,__got (measured with `llvm-objdump --macho --dyld-info`, counted per dependency
 * field, never by substring):
 *
 *   _CECRuntime               (data)  the global runtime reference
 *   _CEContextIsSubset        (function)
 *   _CEManagedContextFromCFData (function)
 *   _CEReleaseManagedContext  (function)
 *   _CESerializeCFDictionary  (function)
 *   _kCENoError               (data)  the "no error" CE_Error_t constant
 *
 * The shapes below are taken from the CLIENT's call sites (the contract), not invented, and each
 * name is in Apple's own stub: ...
 *   <Xcode>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/libCoreEntitlements.tbd
 * (measured: that file declares install-name '/usr/lib/libCoreEntitlements.dylib' and carries all
 * six names above). The .tbd gives names only -- it does not say data vs function, nor arity -- so
 * the rest is read out of DVTPortal's disassembly:
 *
 *   -[DVTPortalProvisioningProfileEntitlementMatchingProvider ceContextForEntitlements:logAspect:]
 *     rax = address of _CECRuntime; r12 = *(rax)                  -> a GLOBAL VARIABLE, not a
 *                                                                   pointer-to-pointer
 *     rdi = r12 (the runtime value); rsi = the CFDictionary; rdx = &local CFDataRef (zeroed)
 *     call _CESerializeCFDictionary                               -> 3 args, returns CE_Error_t
 *     cmp returned, *(&_kCENoError)                               -> kCENoError is a VARIABLE
 *                                                                   holding a error object, compared
 *                                                                   BY POINTER VALUE
 *     rdi = r12; rsi = that CFDataRef; rdx = &local context (zeroed)
 *     call _CEManagedContextFromCFData                            -> 3 args, same return convention
 *   -[... isEntitlementGrantedWithProfile:entitlement:value:logAspect:]
 *     rdi = contextA; rsi = contextB; call _CEContextIsSubset      -> BY VALUE (two words), ret err
 *     lea &contextSlot, %rdi; call _CEReleaseManagedContext        -> address of the slot
 *
 * WHAT IT ANSWERS, AND WHY THAT IS THE TRUTH. This guest has no entitlement engine at all: it
 * parses no code signature, reads no DER entitlement blob, and holds no runtime. So:
 *
 *   CECRuntime = NULL      -- there is no runtime. The value is only ever passed back into the
 *                             functions below, which do not dereference it.
 *   kCENoError             -- a real CFStringRef, because DVTPortal compares the RETURNED error
 *                             against *kCENoError by pointer; the string it holds is this build's
 *                             own ("no error"), which is exactly what the name claims.
 *   the four functions    -- return a DIFFERENT CFStringRef, an explicit failure that says the
 *                             operation cannot be performed here. Returning kCENoError would be a
 *                             LIE: it would tell DVTPortal "these entitlements were serialized and
 *                             parsed, and the subset relation holds", when nothing was parsed.
 *                             Returning an error makes DVTPortal take its own failure path (it
 *                             logs and returns nil), which is the honest outcome for a guest with
 *                             no entitlement machinery.
 *   CEReleaseManagedContext-- a no-op that clears the caller's slot. Nothing was ever allocated, so
 *                             there is nothing to release; the caller passes the ADDRESS of its
 *                             slot, and writing NULL there keeps its later use well-defined.
 *
 * NOT IMPLEMENTED, and deliberately named: the DER entitlement codec (single-value extractors,
 * serialization, the query API, the whole der_vm_* surface) is absent. Nothing demands it in the
 * ladder's closure; a client that needs it gets the explicit error above rather than a wrong
 * answer. No "STUB:" string is printed anywhere: these answers are the truth, not a placeholder.
 */

#include <CoreFoundation/CoreFoundation.h>

/* Apple's own names and link-time shape. CE_Error_t is a CFStringRef: the client compares the
 * returned value with *kCENoError by pointer, which only works if the return type is the same
 * object type the constant holds. */
typedef CFStringRef CE_Error_t;
typedef CFTypeRef CE_RuntimeRef;
typedef CFTypeRef CE_ManagedContext_t;

/* Data symbols. Their ADDRESS is bound in the client's __got, so each must be a real object with
 * external linkage; `const` keeps them read-only, which is what the name says. */
CE_RuntimeRef CECRuntime = NULL;
const CE_Error_t kCENoError = CFSTR("no error");

/* The explicit failure this image answers with. A single object identity, so a caller that compares
 * two failures sees the same object, as it would with Apple's error constants. */
static const CE_Error_t kCENotImplemented = CFSTR(
	"libCoreEntitlements is not implemented in this guest: no code signature and no entitlement "
	"blob is parsed, so this operation cannot be performed");

/* Every one of the four functions answers with the same explicit failure. The signatures are
 * DVTPortal's call sites, above; the parameter names are what the call sites pass. */
CE_Error_t CESerializeCFDictionary(CE_RuntimeRef runtime, CFDictionaryRef entitlements,
	CFDataRef *serialized)
{
	(void)runtime; (void)entitlements;
	if (serialized) {
		*serialized = NULL;
	}
	return kCENotImplemented;
}

CE_Error_t CEManagedContextFromCFData(CE_RuntimeRef runtime, CFDataRef serialized,
	CE_ManagedContext_t *context)
{
	(void)runtime; (void)serialized;
	if (context) {
		*context = NULL;
	}
	return kCENotImplemented;
}

CE_Error_t CEContextIsSubset(CE_ManagedContext_t subset, CE_ManagedContext_t superset)
{
	(void)subset; (void)superset;
	return kCENotImplemented;
}

void CEReleaseManagedContext(CE_ManagedContext_t *context)
{
	/* Nothing was ever allocated for this caller (no context can be created), so the release is a
	 * no-op; clearing the slot keeps the caller's own bookkeeping consistent. */
	if (context) {
		*context = NULL;
	}
}
