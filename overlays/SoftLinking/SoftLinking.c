/*
 * SoftLinking.framework -- a REAL implementation of the two entry points Apple's private
 * /System/Library/PrivateFrameworks/SoftLinking.framework exports.
 *
 * WHY IT EXISTS. The Xcode 26.3 load-time ladder stops here:
 *
 *   Library not loaded: /System/Library/PrivateFrameworks/SoftLinking.framework/Versions/A/SoftLinking
 *   Referenced from: .../Frameworks/IDEFoundation.framework/Versions/A/IDEFoundation
 *
 * Both the install name and the export set are Apple's: its stub file in the same SDK
 * (<Xcode>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/
 * SoftLinking.framework/Versions/A/SoftLinking.tbd) declares install-name
 * /System/Library/PrivateFrameworks/SoftLinking.framework/Versions/A/SoftLinking, current-version
 * 67, and exactly two symbols -- __sl_dlopen and __sl_dlopen_audited. IDEFoundation's LC_LOAD_DYLIB
 * asks for compatibility version 1.0.0 at current version 67.0.0 and binds ONE of them.
 *
 * THE DEMAND, measured from the referrer and never by substring (`llvm-objdump --macho
 * --dyld-info`, x86_64 slice): the dependency field `SoftLinking` carries one symbol, bound
 * EAGERLY and non-lazily in __DATA_CONST,__got (slot 0xCC2300):
 *
 *   __sl_dlopen
 *
 * and the whole image holds exactly ONE call to it (0x23221f, `callq ## symbol stub for:
 * __sl_dlopen`, inside ____ZL29getSCNStatisticsProviderClassv_block_invoke). __sl_dlopen_audited
 * is demanded by nothing in this closure: no binary in the Xcode tree binds it, only the tbd names
 * it. It is implemented here because the tbd, which is the ABI, lists it.
 *
 * WHAT THE CALLER ACTUALLY PASSES, and this is the signature this file implements. Read off the two
 * call sites that exist in this Xcode (IDEFoundation's SceneKit helper and AccessibilityKit's
 * AccessibilitySharedSupport helper), which agree register for register:
 *
 *   rdi = a pointer to a 24-byte, NULL-terminated array of three `const char *` copied to the
 *         stack from a template in __DATA_CONST,__const (`movq`/`movaps` from 0xccff10 in
 *         IDEFoundation; 0x63aa0 in AccessibilityKit). The three entries, in order, are
 *
 *           [0] the image path as it sits INSIDE the "softlink:r:path:<path>" directive that the
 *               compiler wrote to __TEXT,__dlopen_cstrs (IDEFoundation: 0xc34a20, the text after
 *               the 16-byte prefix of the directive at 0xc34a10; AccessibilityKit: 0x612f0 in the
 *               directive at 0x612e0),
 *           [1] the same path as a plain __TEXT,__cstring literal (IDEFoundation: 0xaf0c85;
 *               AccessibilityKit: 0x5e5da), and
 *           [2] NULL.
 *
 *   rsi = a pointer to a `char *` the caller initializes to NULL and reads afterwards. The caller
 *         frees it (`callq _free`) when it is non-NULL and the handle came back, and prints it with
 *         `abort_report_np("%s", ...)` when the handle did not -- so it is a malloc'd message that
 *         belongs to the caller, not a buffer to fill in place.
 *
 *   returns rax, a `void *` the caller stores as the framework's dlopen handle (and NULL is the
 *   failure the caller checks first).
 *
 * The two paths and the array shape are not a guess: ld64's open source names the structure. In
 * apple-oss-distributions/ld64, src/ld/passes/dylibs.cpp keeps these directives in
 * `SoftLinkAuditAtom::_s_section("__TEXT", "__dlopen_cstrs", ...)`, parses them with
 * `strncmp(str, "softlink:", 9)` / `strncmp(&str[11], "path:", 5)` / `const char* path = &str[16]`
 * (the offsets this file uses), and when it rewrites such a path it says so in the two places the
 * array has: "switch dlopen string to use new path" (the __cstring entry) and "switch paths array
 * to use new path" (the __DATA_CONST entry). It also notes "if this was built for older OS,
 * _sl_dlopen glue is inlined", which is the shape seen here: the glue is inlined into the caller.
 *
 * WHAT THIS IMPLEMENTATION DOES. It reads the argument as what the caller builds and what ld64
 * calls it -- a NULL-terminated list of candidate paths -- and tries each in order:
 *
 *   * An entry that starts with the "softlink:" prefix is a directive; the only directive it
 *     interprets is "path", whose value starts at byte 16 (ld64's own offsets). An entry that is
 *     not a directive is a path as it stands. The two-byte flag token between the prefix and the
 *     directive name ("r" in every directive measured here) is NOT interpreted: neither Apple nor
 *     ld64 documents its meaning, and this file does not invent one.
 *   * The path is opened with dlopen(path, RTLD_LAZY | RTLD_LOCAL). The mode is this
 *     implementation's choice -- Apple does not publish one and the caller supplies none -- and it
 *     is the soft-linking mode: bind lazily (a soft-linked framework is exactly one whose symbols
 *     may be missing) and keep the image out of the global namespace.
 *   * On success the handle is returned and the message out-parameter is left NULL (nothing to
 *     report, nothing for the caller to free). On failure of every candidate, the message
 *     out-parameter receives a malloc'd single line naming the last path tried and dlopen's own
 *     reason for it, and NULL is returned -- which is what the caller then prints and aborts on.
 *     A call in which no entry was even readable (an unknown directive, or an empty array) leaves a
 *     line saying so instead, so a failed load always gives the caller something to print.
 *   * __sl_dlopen_audited is the same load with the audit taken: it reports the failure on stderr
 *     as well as through the out-parameter. Nothing in the measured closure calls it (only Apple's
 *     tbd names it), so the reporting sink is the only thing this file chooses: Darling has no
 *     SoftLinking audit facility, and stderr is where a library's failure line belongs.
 *
 * WHAT THIS FILE DOES NOT DO. It does not stub, guess or no-op anything: both entry points perform
 * a real dlopen, and the only strings they produce are the image path and dlopen's reason for it.
 * It does not implement the "r" flag, any directive other than "path", or any entry point Apple's
 * tbd does not list (there are none).
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The directive grammar, with ld64's own offsets (src/ld/passes/dylibs.cpp). */
#define SL_PREFIX "softlink:"
#define SL_PREFIX_LEN 9
#define SL_DIRECTIVE_OFFSET 11
#define SL_VALUE_OFFSET 16

/*
 * The path an entry names, or NULL when the entry is a directive this library does not know how to
 * read (which is reported as a failure rather than opened as a path: dlopen("softlink:...") would
 * fail anyway, with a message about the wrong string).
 */
static const char *sl_path_from_entry(const char *entry)
{
	if (strncmp(entry, SL_PREFIX, SL_PREFIX_LEN) != 0)
		return entry;
	/* An entry too short to hold a directive is not a path -- and must not be read past its end
	   looking for one. */
	if (strlen(entry) < SL_VALUE_OFFSET)
		return NULL;
	if (strncmp(entry + SL_DIRECTIVE_OFFSET, "path:", 5) != 0)
		return NULL;
	return entry + SL_VALUE_OFFSET;
}

/* "<path>: <reason>", malloc'd for the caller, or NULL when the allocation fails. */
static char *sl_message(const char *path, const char *reason)
{
	int length = snprintf(NULL, 0, "%s: %s", path, reason);
	char *message;

	if (length < 0)
		return NULL;
	message = malloc((size_t)length + 1);
	if (message != NULL)
		snprintf(message, (size_t)length + 1, "%s: %s", path, reason);
	return message;
}

/* The ABI names are __sl_dlopen and __sl_dlopen_audited (two underscores), as Apple
   SoftLinking.tbd lists them and as IDEFoundation binds them.  Mach-O prefixes every C
   identifier with one underscore, so the C definitions must be _sl_dlopen /
   _sl_dlopen_audited: writing the leading underscore twice exported ___sl_dlopen, which the
   eager bind could never satisfy (dar-softlinking-extra-underscore-3k11). */
void *_sl_dlopen(const char *const *paths, char **message)
{
	const char *lastTried = NULL;
	const char *reason = NULL;
	size_t index;

	if (message != NULL)
		*message = NULL;

	if (paths != NULL) {
		for (index = 0; paths[index] != NULL; index++) {
			const char *path = sl_path_from_entry(paths[index]);
			void *handle;

			if (path == NULL || path[0] == '\0')
				continue;

			/* Clear any stale error so the reason below belongs to THIS dlopen. */
			(void)dlerror();
			handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
			if (handle != NULL)
				return handle;

			lastTried = path;
			reason = dlerror();
		}
	}

	/* Every failure gets a message: the caller prints it and aborts on the NULL handle, and an
	   empty report ("(null)") would say nothing about what could not be loaded. */
	if (message != NULL) {
		if (lastTried != NULL)
			*message = sl_message(lastTried, reason != NULL ? reason : "image not found");
		else if (paths != NULL && paths[0] != NULL)
			*message = sl_message(paths[0], "no candidate path this library can read");
		else
			*message = sl_message("SoftLinking", "no candidate paths were supplied");
	}
	return NULL;
}

void *_sl_dlopen_audited(const char *const *paths, char **message)
{
	void *handle = _sl_dlopen(paths, message);

	if (handle == NULL) {
		const char *reason = (message != NULL && *message != NULL)
			? *message : "no candidate path could be opened";
		fprintf(stderr, "SoftLinking: a soft-linked image could not be loaded: %s\n", reason);
	}
	return handle;
}
