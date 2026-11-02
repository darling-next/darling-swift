#!/usr/bin/env python3
"""Extract the fork's own CMakeLists source lists for the targets CryptoKit needs.

The lists are the authoritative definition of the module (the fork ships them), so this reads them
rather than keeping a second, hand-maintained list that would drift.
"""
import re, sys, os
SRC = sys.argv[1]
OUT = sys.argv[2]
def quoted(text):
    out, i = [], 0
    while True:
        i = text.find('"', i)
        if i < 0: return out
        j = text.find('"', i + 1)
        if j < 0: return out
        out.append(text[i+1:j]); i = j + 1

def gen_expr(text):
    # $<$<COND:path>  -> path
    # $<$<COND:...>:path> -- the inner condition contains its own '>', so match the closing
    # '>:path>' rather than trying to balance the brackets.
    return [m.group(1) for m in re.finditer(r'>:([^>]+)>', text)]

def section(text, start_pat, end_pat):
    m = re.search(start_pat, text)
    if not m: return ""
    rest = text[m.end():]
    e = re.search(end_pat, rest)
    return rest[:e.start()] if e else rest

def main():
    ctext = open(os.path.join(SRC, "Sources/CCryptoBoringSSL/CMakeLists.txt")).read()
    files = []
    files += quoted(ctext) + gen_expr(ctext)
    # the Darwin/x86_64 asm block is unquoted
    blk = section(ctext, r'if\(CMAKE_SYSTEM_NAME STREQUAL Darwin AND CMAKE_SYSTEM_PROCESSOR MATCHES "amd64\|x86_64"\)', r'elseif|endif')
    files += re.findall(r'[A-Za-z0-9_./+-]+\.(?:S|s)\b', blk)
    c = sorted({f for f in files if f.endswith(('.cc', '.c', '.S', '.s'))})
    k = ["CXKCP/" + f for f in quoted(open(os.path.join(SRC, "Sources/CXKCP/CMakeLists.txt")).read()) if f.endswith(('.c', '.cc', '.S'))]
    k += ["CXKCPShims/" + f for f in quoted(open(os.path.join(SRC, "Sources/CXKCPShims/CMakeLists.txt")).read()) if f.endswith(('.c', '.cc', '.S'))]
    sw = sorted(set(quoted(open(os.path.join(SRC, "Sources/Crypto/CMakeLists.txt")).read())))
    sw = [f for f in sw if f.endswith('.swift')]
    bw = sorted(set(quoted(open(os.path.join(SRC, "Sources/CryptoBoringWrapper/CMakeLists.txt")).read())))
    bw = [f for f in bw if f.endswith('.swift')]
    for name, lst in (("BORINGSSL", c), ("XKCP", k), ("CRYPTO_SWIFT", sw), ("WRAPPER_SWIFT", bw)):
        print("%s %d" % (name, len(lst)))
        with open(os.path.join(OUT, "list-%s.txt" % name.lower()), "w") as h:
            for f in lst: h.write(f + "\n")
main()
