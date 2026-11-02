// Compile with the canonical source-built Darwin module, disable its direct
// autolink, and link only through split reexport libraries (see README).
// Run against the normally installed Darling image, never injected dylibs.
import Darwin

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

// errno must be the same thread-local storage used by libc, including _modify.
errno = 0
check(close(-1) == -1, "close must fail")
check(errno == EBADF, "libc and Swift errno must share storage")
func change(_ value: inout Int32) { value = EINVAL }
change(&errno)
check(__error().pointee == EINVAL, "errno inout must update libc storage")

// The UNIX2003 socket code is distinct from the historical ENOTSUP alias.
check(POSIXErrorCode.EOPNOTSUPP.rawValue == EOPNOTSUPP, "socket error code")
check(POSIXErrorCode(rawValue: 102) == .EOPNOTSUPP, "raw socket error")
check(POSIXErrorCode(rawValue: 107) == .ENOTCAPABLE, "capability error")
check(POSIXErrorCode.ELAST == .ENOTCAPABLE, "largest errno")
check(POSIXErrorCode.EWOULDBLOCK == .EAGAIN, "would-block alias")

// Transparent math APIs may inline to libc; these assertions check semantics,
// not runtime coverage of the out-of-line Swift math entrypoints.
let input = Double(CommandLine.arguments.count)
check(abs(sin(input) * sin(input) + cos(input) * cos(input) - 1) < 1e-12, "Double math")
let single = Float(input)
check(abs(sin(single) * sin(single) + cos(single) * cos(single) - 1) < 1e-6, "Float math")
#if arch(x86_64)
let extended = Float80(input)
check(abs(sin(extended) * sin(extended) + cos(extended) * cos(extended) - 1) < 1e-15, "Float80 math")
#endif

var text = [CChar](repeating: 0, count: 32)
let count = "ok".withCString { word in
    text.withUnsafeMutableBufferPointer {
        snprintf(ptr: $0.baseAddress!, $0.count, "%d:%s", Int32(42), word)
    }
}
check(count == 5 && String(cString: text) == "42:ok", "stdio variadic bridge")
check(stdout == __stdoutp, "stdio shared pointer")
let duration = Duration.seconds(3) + .milliseconds(250)
let ts = timespec(duration)
let tv = timeval(duration)
check(ts.tv_sec == 3 && ts.tv_nsec == 250_000_000, "timespec conversion")
check(tv.tv_sec == 3 && tv.tv_usec == 250_000, "timeval conversion")
check(Duration(ts) == duration && Duration(tv) == duration, "duration round-trip")
check(SIG_DFL == nil, "default signal handler")
check(unsafeBitCast(SIG_IGN, to: Int.self) == 1, "ignored signal handler")
print("darwin_split: PASS")
