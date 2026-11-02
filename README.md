# Darling Swift

Attention: This repository uses Git LFS!

Git LFS derives its endpoint from the selected Git remote. There is no fixed
upstream `.lfsconfig`: a fork must serve the payloads referenced by its own
commits. Publish SHA-256/size-verified payload objects before the corresponding
Git refs. For a migration, select the reviewed object IDs explicitly with
`git lfs push --object-id`; do not upload every object in a mixed local store.

Files found here come from official Swift releases from Swift.org. They are downloaded and extracted using the `build.sh` script before committing.

## The payload must match the guest's Swift compiler

`version.txt` is not a free choice. These dylibs are the runtime that guest
Darwin binaries load from `/usr/lib/swift/`, and a binary built by a given Swift
toolchain calls stdlib symbols that only a runtime of the same vintage defines.

Measured 2026-10-11 with Xcode 26.3 (toolchain `Swift version 6.2.4`, SDK 26.2):
the 5.2.2 payload installed and guest `dyld` loaded the toolchain's own `swiftc`,
which then aborted on

    Symbol not found: _$sSS27unsafeUninitializedCapacity20initializingUTF8WithSSSi_SiSrys5UInt8VGKXEtKcfC
      Referenced from: ...XcodeDefault.xctoolchain/.../lib/swift/host/compiler/lib_CompilerSwiftSyntax.dylib
      Expected in: /usr/lib/swift/libswiftCore.dylib

The compiler ran; the runtime was six years too old. The toolchain does not carry
a usable copy of its own system runtime (`usr/lib/swift/macosx` holds only
`libLiveExecutionResultsLogger.dylib` and `libPlaygrounds.dylib`), because on a
real Mac the runtime comes from the OS -- so the matching runtime has to be
fetched from Swift.org, which is exactly what `build.sh` does. Bump `version.txt`
to the version `swift-frontend` reports for the toolchain in use, never to an
arbitrary newer one, and never pin an old one "because it worked": a mismatch is
silent until a guest program calls a stdlib entry point that moved.

## x86_64 slices built on Linux

`libswiftDarwin.dylib`, `libswiftObjectiveC.dylib`, `libswiftCoreFoundation.dylib`
and `libswiftDispatch.dylib` in this directory are x86_64-only. They were built
here, on Linux, from this repository's `overlays/` sources, not downloaded:

* Swift 6.3.1 release toolchain (`swift-6.3.1-RELEASE-ubuntu24.04`), which
  cross-compiles to `x86_64-apple-macosx26.0`;
* resource directory from the `usr/lib/swift` of `swift-6.3.1-RELEASE-osx.pkg`
  (the `SwiftShims` and `_Concurrency` modules and the clang headers the
  overlays need);
* `-swift-version 5 -enable-library-evolution`, the flags `overlays/build.sh`
  uses for the arm64 slices;
* linked against Darling's own `libSystem.B.dylib`, `libobjc.A.dylib` and
  `CoreFoundation` out of a Darling build.

They carry only the x86_64 architecture: the arm64 halves of the universal
files VibeDarling built are not in this working tree (their git-LFS objects are
absent, so the recorded versions smudge to pointers), and were therefore not
merged in. The arm64 build of the same sources is what restores a universal
file.

Built in this pass, all x86_64 Mach-O (bytes):

| file | bytes |
| --- | --- |
| `libswiftDarwin.dylib` | 69784 |
| `libswiftObjectiveC.dylib` | 36340 |
| `libswiftCoreFoundation.dylib` | 858232 |
| `libswiftDispatch.dylib` | 293120 |
| `libswiftos.dylib` | 56224 |
| `libswiftXPC.dylib` | 70348 |
| `libswiftFoundation.dylib` | 7764520 |
| `Combine.framework/Versions/A/Combine` | 1858780 |
| `CryptoKit.framework/Versions/A/CryptoKit` | 3061672 |

`libswiftFoundation` is the last of these and the reason the others exist: it is
what makes `PropertyListDecoder` resolvable, the symbol Xcode 26.3's
prerequisite framework asks for. It links against Darling's Foundation,
CoreFoundation, libicucore, the Combine binary above and the ld64 flags
`overlays/build-arch.sh` uses.

The following is a historical build observation, not a deployment recipe.

Two things this pass needed from the product side, both now in the tree:

* the framework's headers are VibeDarling's (their include/Foundation at
  `607ec56da3d40eac8512514b1aceb4d4d0322d82`); ours were older and the difference
  was member level, which API notes cannot bridge;
* Darling's Foundation library gained `NSPersonNameComponents` and
  `NSInlinePresentationIntentAttributeName`, without which the overlay compiles
  but does not link. The built slice (6270308 bytes, i386 + x86_64) is at
  `<build>/src/external/foundation/Foundation` and is NOT installed: the
  tree's CMAKE_INSTALL_PREFIX is the running root, so deploying it is a separate
  step. Until it is deployed, `libswiftFoundation.dylib` here has those two
  symbols undefined, exactly as on a system where the library predates them.

### Normal product installation

Darling's normal build links these vendored Swift dylibs and the Combine binary
directly; it needs no staging target or prior installation. The Swift member's
normal install rules ship the dylibs, complete framework bundles and resources.
After updating an owned payload, build the complete product and run
`cmake --install <build>` with its final absolute `CMAKE_INSTALL_PREFIX` set to a
new runtime root `R`. Do not overwrite a published image or copy individual system
libraries into writable guest state `P`. Select the installed launcher separately:
`DPREFIX="$P" "$R/bin/darling" shell ...`. Build/install success is not guest API or
workload acceptance.

`overlays/` is this payload's copy of the overlay sources, so the tree carries
the tree that builds the files next to it. One of them is Darling's change to
VibeDarling's file: `overlays/os/os.swift` re-exports the `os.log` Clang
submodule (`@_exported import os.log`, with the reason in a comment there),
because the Swift os module's public API names `OSLog`, which lives in an
explicit submodule its clients otherwise cannot see.

## Foundation value and string boundaries

The Foundation overlay preserves UTF-16-relative line ranges for `String` and
the original index base for `Substring`. Hard-line enumeration delegates to the
native NSString scanner, retaining empty lines and respecting early stop.
The inherited scanner bounds both its forward scan and its EOF lookup, including
Swift-backed NSString subclasses rather than only `NSCFString`.

`URL.host(percentEncoded:)` resolves base URLs, keeps IPv6 brackets out of the
host value and uses ICU's UTS #46 conversion before percent-encoding Unicode
host bytes. File URLs expose `canonicalPath` through the native guest `realpath`
resource operation, without populating unrequested resource keys.
`CocoaError.error(_:userInfo:url:)` retains the typed Cocoa code and lets an
explicit URL override the user-info URL.

`overlays/tests/foundation_value_semantics.swift` exercises those boundaries
through the actual SDK consumer, including relative symlinks and unterminated
Unicode lines. Its temporary C pathname buffer stays borrowed until the returned
path has been copied into Swift storage.

## AppleArchive callback status boundary

`libswiftAppleArchive` exposes the genuine `ArchiveHeader.EntryMessageStatus`
scalar contract: signed 32-bit raw values, `ok` (0), `skip` (1), `cancel` (-1),
and value equality/hashing. Unknown raw values remain representable; construction
does not perform an archive operation. This is not an implementation of the
unavailable Apple Archive compression/container engine.

The focused `DARLING_SWIFT_APPLEARCHIVE_ONLY=1` route in
`overlays/build-arch.sh` consumes the real SDK `System.swiftmodule` selected by
`SWIFT_SYSTEM_MODULES` and links the actual `libswiftSystem.dylib` provider.
It does not suppress unresolved System metadata or import unrelated SDK modules.

## CryptoKit

`CryptoKit.framework/Versions/A/CryptoKit` is [swift-crypto](https://github.com/apple/swift-crypto)
(Apache-2.0 with the Runtime Library Exception) built as module `CryptoKit`, so its mangled names
match what clients of Apple's CryptoKit bind. `build-cryptokit.sh` next to this file builds it, from
the `darling/cryptokit-module` branch of the
[cristim/swift-crypto](https://github.com/cristim/swift-crypto) fork at commit
`c4105ade5fbe6866375ec65146cac733d53a1146` — fetched by the script, never vendored — with the same
toolchain and resource directory as the overlay slices above. The local
`cryptokit-darling.patch` is applied to that exact source before compiling.
It removes `@inlinable` from the existing key-wrapper initializers and selects
the upstream buffer-based AEAD decrypt path instead of Foundation's newer
`Data.mutableBytes` property. No cipher, signature algorithm, or authentication
check is replaced.

The former patch also excluded P-384/P-521 signing because the original hash
subset lacked SHA-384/512. Those exclusions are removed: the pinned fork's real
ECDSA implementation now uses the existing `cryptokit-sha384sha512.swift`
hashers. The full upstream AES-GCM/ChaChaPoly AEAD sources and BoringSSL wrapper
are selected, not a metadata-only `AES.GCM` declaration. ChaChaPoly is included
because the upstream nonce source declares both AEAD nonce types.

### Ed25519 software signatures

The selected source includes the pinned fork's complete `Curve25519.Signing`
public/private-key family and its BoringSSL Ed25519 backend. Public-key
construction requires 32 bytes and signature verification requires 64 bytes.
Contiguous message/signature inputs are borrowed; only discontiguous
`DataProtocol` regions are flattened before `CCryptoBoringSSL_ED25519_verify`.
No replacement signature algorithm or successful unsupported fallback is used.

`overlays/tests/cryptokit_ed25519.swift` is an independent consumer of RFC 8032
vectors, including the empty message, a longer message, tampered inputs,
segmented/empty regions and invalid key/signature lengths. Compile it inside
Darling with the actual Xcode SDK and run it against the normally installed
framework. This is verification coverage, not a claim that the fixture exercises
private-key generation or every signing overload.

### Secure Enclave capability

`cryptokit-secureenclave.swift` implements the **currently absent provider's
capability contract**, not Secure Enclave hardware or a software emulation of it:

* `SecureEnclave.isAvailable` is false.
* Every P-256 signing/key-agreement generation and opaque-data restoration
  initializer throws `NSError` in `NSOSStatusErrorDomain` with
  `errSecUnimplemented` (-4). Signing (both digest and data overloads) and key
  agreement also fail with this error. There is no successful fallback.
* The SDK's nonthrowing `publicKey` and `dataRepresentation` properties are
  immutable stored fields of resilient, non-`@frozen` values. No initializer
  produces a value on this backend, so no fake public key, serialized key, trap
  getter, or exported software private key is needed.
* `cryptokit-shims/` imports genuine Security/LocalAuthentication SDK headers,
  which lack Clang module maps in this SDK. It does not redeclare their ABI.

The declaration authority is the read-only Xcode 26.3 macOS SDK
`CryptoKit.swiftinterface` and Apple's
[SecureEnclave documentation](https://developer.apple.com/documentation/cryptokit/secureenclave).
Apple documents availability and throwing construction but not the exact error
identity for an absent provider. The error above is **Darling policy**, not an
assertion of Apple's exact error parity: the vendored Security `SecItem.c`
already maps CryptoTokenKit's NotImplemented error to `errSecUnimplemented`.
`errSecNotAvailable` would incorrectly describe the whole keychain as absent.

Authoritative implementation research, before introducing this contract:

* The canonical `cristim/swift-crypto` pin above has no SecureEnclave/SecKey
  implementation. Its ECDSA files have no P-384/P-521 exclusion; those
  exclusions came from this tree's old patch, not the pin.
* [Apple swift-crypto](https://github.com/apple/swift-crypto) at
  `57de8e7cb840b1a608f0cc2221d8f2bda117606c` explicitly excludes
  hardware-dependent functionality and reexports the system CryptoKit on Apple
  platforms. That is circular when building CryptoKit itself. Swift Crypto also
  disclaims stable binary ABI; a source build must retain the named module and
  library-evolution flags, not relabel a prebuilt `Crypto` module.
* Reviewed sibling forks PureSwift (`46eca5f54b62e9ced10fa38c85d6aaa70f3aaed5`),
  classicvalues (`c7a7e877c4590acd3104d6348b38883aaa730132`), and yim-lee
  (`c433cd3341e14590ba7efccb0836cd3cd0a0c055`) contain no SecureEnclave/SecKey
  implementation. The local VibeDarling Swift submodule is unpopulated.
* The Xcode SDK supplies link stubs and interfaces, not a reusable loadable
  system CryptoKit implementation. No proprietary framework binary is copied.
* Vendored Security has real CTK key public-key/signing dispatch
  (`OSX/sec/Security/SecCTKKey.m`), but it depends on `TKTokenCreate`,
  `TKTokenCreateOrUpdateObject`, `TKTokenCopyPublicKeyData`, and
  `TKTokenCopyOperationResult`. Darling's `CryptoTokenKit/src/ctkclient.c`
  returns NULL for all four. The CTK descriptor also has no
  `copyExternalRepresentation` callback: ordinary SecKey export is not an
  implementation of CryptoKit's opaque enclave key representation.

Enabling availability requires a real hardware token provider, authoritative
opaque-key restoration, authenticated public-key access, and signing/key
agreement through that provider. Software BoringSSL keys must never inhabit
these types or be advertised as enclave-backed keys.

### Rebuilding the generated CryptoKit payload

The build requires the host Linux Swift compiler plus its matching Darwin
resource directory, this prepared Darling SDK/libc++ source, ld64 from the
current prepared build, a complete immutable product image for link inputs, and
source-built x86_64 overlay modules. Neither `/tmp` caches nor a default prefix
is an input authority. For this workspace, from the manifest directory:

```bash
export PATH="/usr/lib/llvm-18/bin:$HOME/.local/bin:$PATH"
export WORK=/home/ilyagulya/work/wr-fresh
export PRODUCT="$WORK/.west-state/cutover-gtci/source/darling"
export PAYLOAD="$PRODUCT/src/external/swift"
export STATE="$WORK/.west-state/ios-archive-j17"
export BUILD="$WORK/.west-state/cutover-gtci/build"
export SWIFT_TOOLCHAIN=/home/ilyagulya/work/downloads/swift-linux/swift-6.3.1-RELEASE-ubuntu24.04/usr
export SWIFT_RESOURCE_DIR=/home/ilyagulya/work/local-target/swiftpkg/stage/usr/lib/swift
export DARLING_SDK="$PRODUCT/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
export DARLING_LD="$BUILD/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld"
export DARLING_ROOT="$WORK/.west-state/cutover-gtci/runtime-47/libexec/darling"
export DARLING_LIBSYSTEM="$DARLING_ROOT/usr/lib/libSystem.B.dylib"
export DARLING_LIBCXX_HEADERS="$PRODUCT/src/external/libcxx/include"
export OVERLAY_BUILD_DIR="$STATE/cryptokit-overlay-prerequisites-r48"
export OVERLAY_MODULES="$OVERLAY_BUILD_DIR/modules"
export OVERLAY_LIBRARIES="$PAYLOAD"
export CRYPTOKIT_BUILD_DIR="$STATE/cryptokit-framework"
export SWIFT_DARWIN_ARCH=x86_64
export SWIFT_DARWIN_TARGET=x86_64-apple-macosx26.0
# Needed only when matching source-built overlay modules do not already exist.
# The existing focused route builds Foundation and its module prerequisites;
# it updates Combine's source payload, but leaves the other overlay payloads alone.
DARLING_SWIFT_FOUNDATION_ONLY=1 mise exec -- bash "$PAYLOAD/overlays/build-arch.sh"
mise exec -- bash "$PAYLOAD/build-cryptokit.sh"
```

The overlay generator's additional pinned inputs are declared in that script:
OpenCombine `10df981a64800643559490d72174f43438562e73`, swift-collections
`c11818f3cae0780656baa430b49e7f163f08dffd`, swift-cmark
`924936d0427cb25a61169739a7660230bffa6ea6`, and swift-foundation
`dbacc67779dc0a41ddc9493acbaa332d76c9fb03`. Preserve their source checkouts for
offline replay. The CryptoKit build directory must start with an unmodified
checkout of its declared pin; patch drift is an error, not silently ignored.
The compiler uses `DARLING_SDK` for headers; the linker uses the complete
`DARLING_ROOT` library provider, including libSystem's transitive dependencies.

After the full CryptoKit link succeeds, the script updates the source-owned
`CryptoKit.framework/Versions/A/CryptoKit` generated payload. Existing
`CMakeLists.txt` installs that framework during the normal complete product
publication; it must not be copied into guest state or an existing runtime.
The host cross-compiler here is a framework build input; the workload continues
to use Xcode's actual Swift 6.2.4 without changing its version or architecture.

### Required behavioral smoke

`overlays/tests/cryptokit_provider.swift` is a standalone guest fixture:
unavailable capability, default and explicit-access-control generation for both
P-256 families, empty/nonempty restoration failure with exact Darling error
domain/code, AES-GCM known ciphertext/tag plus tamper rejection, and real
P-384/P-521 digest signing/verification plus changed-digest rejection.
Compile and run it inside the newly published complete Darling image with
Xcode's actual Swift compiler and macOS SDK. This checks consumer ABI as well as
the implementation; do not pass a Swift 6.3 module to the Swift 6.2 compiler.
Success requires rc=0 and `CRYPTOKIT_PROVIDER_PASS`. Never manufacture an unsafe
enclave value to invoke signatures: successful construction is intentionally
impossible, so signature-body failure remains a source contract.

Also compare every actual SwiftPM CryptoKit import with the rebuilt framework's
exports and rerun the genuine source `swift build -c release --arch x86_64`.
The original census was 103 imports, 85 present and 18 absent: five enclave
signing bindings, the AES.GCM nominal descriptor, and six P-384 plus six P-521
signing bindings. Symbol presence is not cryptographic behavior; it does not
replace the smoke or real SwiftPM build. Historical binary measurements below
predate these source changes and are not acceptance of a regenerated image.

### `Insecure.MD5` and `Insecure.SHA-1` (added 2026-10-13, for Notarization)

`Insecure.MD5` and `Insecure.SHA1` are declared in swift-crypto's
`Sources/Crypto/Insecure/Insecure_HashFunctions.swift`, and `build-cryptokit.sh` did not compile that
file — it compiled only `Insecure/Insecure.swift`, which declares the `Insecure` namespace and the
digest types. The committed binary therefore exported neither hash function, and Xcode 26.3's
`Notarization.framework` binds four of them **eagerly and strongly** (decoded from its own
`LC_DYLD_CHAINED_FIXUPS`; the ladder's live stop line was
`_$s9CryptoKit8InsecureO3MD5V6update13bufferPointerySW_tF`):

| symbol | what it is |
| --- | --- |
| `…8InsecureO3MD5VAEycfC` | `Insecure.MD5.init()` |
| `…3MD5V6update13bufferPointerySW_tF` | `update(bufferPointer:)` |
| `…3MD5V8finalizeAC0D6DigestVyF` | `finalize()` — the caller READS the digest it returns |
| `…3MD5VMa` | type metadata accessor |

Adding the file is not enough on its own: its two hash functions store `DigestImpl<SHA1>` /
`DigestImpl<MD5>`, which under `-D DARLING_CRYPTOKIT_MODULE` is `DarlingDigestImpl`
(`Digests/HashFunctions.swift`), constrained to `DarlingBackedHashFunction`
(`Digests/Darling/Digest_darling.swift`) — and the fork conforms only `SHA256` to that protocol. The
upstream conformances for MD5 and SHA1 live in `Digests/BoringSSL/Digest_boring.swift`, which this
build does not compile either (its protocol is a different shape). **`cryptokit-md5sha1.swift` next to
this file supplies the two missing conformances** from BoringSSL's streaming `MD5_*`/`SHA1_*` entry
points, which are already DEFINED by the committed binary (`llvm-nm --defined-only` shows
`_CCryptoBoringSSL_MD5_Init/_Update/_Final` and `_SHA1_Init/_Update/_Final`), so no algorithm is
written here and no digest is invented — a wrong cryptographic answer would be worse than a refusal,
and this client reads the digest. The context types are the C structs `MD5_CTX`/`SHA_CTX`, copied by
value, which is what `DarlingDigestContext(copying:)` needs. `build-cryptokit.sh` now compiles
`Insecure/Insecure_HashFunctions.swift` and `cryptokit-md5sha1.swift`.

Two build-script repairs came with it, both measured:

* **the shebang is `/bin/bash`, not `/bin/sh`.** The parallel C/C++ step exports its compile function
  with `export -f`, which dash rejects as an illegal option for a special builtin and then **exits
  on**: under `sh` the script stops with rc=2 right after printing the file counts, with an empty
  object directory and no error (measured 2026-10-13).
* **the patch apply is conditional** (see above).

The rebuilt binary is 3052904 bytes (was 3030680), exports 9840 names (was 9724), and every name the
two clients in this closure bind is present. (The SHA-384/512 work below rebuilt it once more: 3061672
bytes, 4113 x86_64 export-trie names -- see that subsection for the measured counts.)

Two things the build needs that no other file here does:

* **BoringSSL's C++ half compiled for the Darwin target with Darling's own
  `src/external/libcxx/include`** — the same libc++ the guest's `/usr/lib/libc++.1.dylib` is built
  from. **No C++ standard library for that target exists anywhere else in this environment**
  (measured: absent from Darling's SDK, from the `swift-6.3.1-RELEASE-osx.pkg` resource directory,
  from the Linux toolchain and from the Xcode toolchain), and BoringSSL's first include is
  `<memory>`. Anything else that builds C++ for this target will hit the same wall.
* **a source list narrower than the package's** — the BoringSSL digest
  implementation conflicts with Darling's digest backend. SHA-3 and
  Curve25519 key agreement remain outside this selected surface; the Ed25519
  signing family and AEADs use their complete upstream implementations.

### `SHA384` and `SHA512` (added 2026-10-13, for CoreDocumentation)

`CoreDocumentation.framework` binds two CryptoKit names its load cannot proceed without — `SHA512`'s
type metadata accessor and its `HashFunction` conformance descriptor (walks #365/#366 of the image's
own chained-fixups bind table, all strong and eager; the loader's live stop line was
`_$s9CryptoKit6SHA512VAA12HashFunctionAAMc`). The image's whole CryptoKit field is 11 binds; the other
nine — the `HashFunction` requirement thunks for `init()`, `update(bufferPointer:)` and `finalize()`,
`SHA512Digest`'s metadata accessor and its `Sequence` conformance descriptor, and the four
`Insecure.MD5` names above — were already answered. No other image in the 254-image load closure
demands a CryptoKit name at all, and none demands `SHA384`.

Why they were absent: swift-crypto declares both hashers in
`Sources/Crypto/Digests/HashFunctions_SHA2.swift` inside `#if !DARLING_CRYPTOKIT_MODULE` (the fork's
SHA-256-only policy for this build), so the compiled file carries no `SHA384`/`SHA512` at all. Their
digests (`SHA384Digest`/`SHA512Digest`) are declared ungated in `Digests/Digests.swift` and were
already in the committed binary — only the hashers were missing. Upstream's BoringSSL conformances
live in `Digests/BoringSSL/Digest_boring.swift`, which this build does not compile: it and
`Digests/Darling/Digest_darling.swift` each declare `HashFunctionImplementationDetails` and their own
`DigestImpl`, so the two cannot both be compiled.

What the client does with them (measured, not assumed): besides the two names, the image binds the
three protocol requirement thunks and `SHA512Digest`'s metadata and `Sequence` conformance. Its
`SwiftDocC.Checksum.sha512(of: Foundation.Data) -> String` (0x6c5140) loads the SHA512 metadata and
the `SHA512 : HashFunction` conformance descriptor, allocates a SHA512 value, calls the protocol's
`init()`, updates it with the data, calls `finalize()`, and walks the digest's bytes through the
`Sequence` conformance to build the string it returns — the digest is read and used, so a wrong digest
is a wrong checksum, never a crash.

**`cryptokit-sha384sha512.swift` next to this file** supplies the two declarations (upstream's text
with the gate removed — the SDK's own `CryptoKit.swiftmodule/x86_64-apple-macos.swiftinterface`
declares them at lines 304/306/316/318–326 and the two `HashFunction` conformances at 1695/1697) and
their `DarlingBackedHashFunction` conformances over BoringSSL's streaming `SHA384_*`/`SHA512_*` entry
points, which are already DEFINED by the committed binary (`llvm-nm --defined-only` shows
`_CCryptoBoringSSL_SHA384_Init/_Update/_Final` and `_SHA512_Init/_Update/_Final`). Both hashers use
`SHA512_CTX` as their context, exactly as BoringSSL's own `SHA384_*` do. No algorithm is written here
and no digest is invented. `build-cryptokit.sh` compiles the file; P-384/P-521
signing now uses these hashers after removal of the obsolete local exclusions.

Measured: the rebuilt binary is 3061672 bytes (was 3052904) and its x86_64 export trie carries 4113
names (was 4089) — 0 removed and 24 added, all of them `SHA384`/`SHA512`'s metadata, metadata-nominal,
witness table, conformance descriptor, `init()`, `update(bufferPointer:)`, `finalize()` and their
`byteCount`/`blockByteCount` accessors. Both deployed prefix roots carry the same trie and the
receipt's two rows match. The digest is real, not merely present: a client built with the same
swiftc/Darwin resource directory/ld64 this framework is built with, against this module's own
swiftmodule and linked to the **deployed** framework, run inside the guest, reproduces the FIPS 180-4
vectors for SHA-512 and SHA-384 — `"abc"`, the 112-byte two-block string and one million `'a'` —
including the one-byte-at-a-time streaming path, and `SHA512.hash(data:).description` matches the same
hex. One property of this module worth recording: because it is built with a plain
`import CCryptoBoringSSL` (and CryptoBoringWrapper), its `CryptoKit.swiftmodule` lists those as
required modules for anyone recompiling against it. The deployed framework does not ship the
swiftmodule and Apple-compiled clients never read it, so it is not a load-time property.

**The demand, measured against Xcode 26.3's own bytes.** `DVTFoundation` binds five CryptoKit symbols
and all five through `__DATA_CONST __got`, so they are eager, non-lazy binds and dyld must resolve
every one at load. Each of the five is defined in this binary — checked with `llvm-nm --defined-only`
against the names read out of DVTFoundation's own dyld info, not against the recipe's idea of them:

| symbol (as DVTFoundation binds it) | where this build defines it |
| --- | --- |
| `…4P256O7SigningO10PrivateKeyV17pemRepresentationAGSS_tKcfC` — `P256.Signing.PrivateKey.init(pemRepresentation:)` | `Key Agreement/ECDH.swift`, the `P256 + Signing` section |
| `…O10PrivateKeyV9signature3forAE14ECDSASignatureVx_tK10Foundation12DataProtocolRzlF` — `signature(for:)` | declared in `Signatures/ECDSA.swift`, witness in `Signatures/BoringSSL/ECDSA_boring.swift` |
| `…O10PrivateKeyVMa` — `PrivateKey` metadata | the `PrivateKey` struct in `Signatures/ECDSA.swift` |
| `…O14ECDSASignatureV17rawRepresentation10Foundation4DataVvg` — `ECDSASignature.rawRepresentation` | `Signatures/ECDSA.swift` |
| `…O14ECDSASignatureVMa` — `ECDSASignature` metadata | the `ECDSASignature` struct in `Signatures/ECDSA.swift` |

Not built in this pass, and therefore not in this repository:
`libswiftCoreGraphics`, `libswiftAppKit`, `libswiftQuartzCore`, `libswiftSceneKit`,
`libswiftUniformTypeIdentifiers`, `libswiftCoreText`, and the `GroupActivities`
framework binary. `CryptoKit` is now built here (above); the next one in line,
`libswiftCoreGraphics`, fails with `cannot find type 'CGAffineTransform'`/`'CGColor'`:
CoreGraphics has Headers but no `Modules/module.modulemap`, and the generator's
`frameworks/<Name>/module.modulemap` mechanism (used for Foundation and
CoreFoundation) is what it needs. Nothing arm64-only was added here to fill any
gap.

## The Swift Network overlay (`libswiftNetwork.dylib`)

`libswiftNetwork.dylib` is this repository's own overlay for Apple's closed-source `Network` module,
built by `overlays/build-arch.sh` (the `build_network` function) into
`/usr/lib/swift/libswiftNetwork.dylib` — the install name Apple used before it moved these names into
`Network.framework` (the SDK's own `Network.tbd` still records the move as
`$ld$previous$/usr/lib/swift/libswiftNetwork.dylib$$1$10.15$14.0$_$s7Network…` entries). Xcode 26.3's
`Notarization.framework` binds **138** of them against its `Network.framework` ordinal (ordinal 12 of
its 24 dylibs), all eager and strong: the image is `LC_DYLD_CHAINED_FIXUPS`, so every import is
applied when it loads and there is no lazy form (measured by decoding the fixup chains: 4084 bind
fixups, 138 in the Network field, 0 of them weak, all in `__DATA_CONST,__got`).

* **declarations** come from the guest SDK's own interface
  (`…/Network.framework/Modules/Network.swiftmodule/x86_64-apple-macos.swiftinterface`); the file
  headers cite the line of each type. Nothing about a signature is invented, and a member the demand
  does not name and this overlay does not implement is simply absent — stated where it would
  otherwise look accidental (Apple's `NWError.dns` case, which no `dnssd` module in Darling's SDK can
  name).
* **the value half is real**: endpoints, hosts, ports, IPv4/IPv6 addresses, the interface descriptor,
  paths and errors are pure data with no dependency on a network stack, and every demanded member of
  them is implemented for real (including IPv6 text parsing and canonical `::` formatting).
* **the transport half is refused, by name.** This guest has no network stack at all: the tree's own
  C API for it, `libnetwork` (re-exported by `Network.framework`), is stubs that print
  `libnetwork stub called: <name>` and return NULL (`nw_connection_create` returns NULL,
  `nw_connection_start` is a print), and Darling's `Security.framework` exports no
  `sec_protocol_options_create`. So `start(queue:)`, `send(…)`, `receive(…)`,
  `startDataTransferReport()`, `requestEstablishmentReport(queue:completion:)` and the two
  `securityProtocol*` members call `darlingNetworkUnserved()` — an explicit `fatalError` naming the
  member and the reason — rather than return a plausible wrong value or a fabricated success.
  `NWListener.init(using:on:)` can throw, so it throws a real Swift error
  (`NSFeatureUnsupportedError`, 3328, the same error the Foundation overlay's `URLSession` returns
  for its unserved async API). What CAN be answered honestly is answered honestly: `state` is
  `.setup`, `currentPath` and `metadata(definition:)` are nil, `batch(_:)` runs its block, `cancel()`
  is a no-op, and the TCP/TLS option containers are real storage.
* **`overlays/Network/shims/module.modulemap`** exists because Darling's SDK has no
  `Security.framework/Modules/module.modulemap`, so `import Security` does not resolve when the
  overlays are built; the shim re-exports only the two protocol-object types the TLS members name,
  and a probe confirms they mangle to exactly what the demand carries
  (`So23OS_sec_protocol_options_p`, `So24OS_sec_protocol_metadata_p`).
* **what the loader reaches**: of the 138, only 25 are referenced by any rip-relative operand in
  Notarization's own code (enum-case constructors, metadata accessors, the `NWPath` endpoint getters
  and the `NWError: Error` conformance descriptor); the rest are bound without a code reference. All
  138 must still resolve at load.

### `NWPathMonitor` and `NWPath.Status` (added 2026-10-13, for ContentDelivery)

Xcode 26.3's `Contents/SharedFrameworks/ContentDelivery.framework/Versions/A/ContentDelivery` binds
eleven more names against the same ordinal — `NWPathMonitor`'s metadata accessor, nominal descriptor,
`init(requiredInterfaceType:)`, `start(queue:)`, `cancel()` and `pathUpdateHandler`'s setter, plus
`NWPath.Status` and its three cases, its metadata accessor and `NWPath.status` — all eager and strong
(imports 251-261 of its chained fixups, `lib_ordinal 6`, `weak_import 0`). They are reached from one
create/handler/start/cancel sequence in that image (0x128d56-0x129177), and its handler READS
`path.status` and maps it to 1/0/2/-1 for satisfied/unsatisfied/requiresConnection/unknown, so the
value is used.

* **the monitor is real state, and the one observation is this guest's own**: there is no path. The
  tree says so itself — libnetwork answers every path query with a stub (`nw_path_get_status` returns
  `nw_path_status_invalid`, `nw_path_monitor_create` returns NULL,
  `src/external/libnetwork/src/nw/path.m:141-147,179-215`) — and `NWPath.Status.unsatisfied` is Apple's case
  for exactly that, so `start(queue:)` delivers the unsatisfied current path once on the given queue,
  as Apple's monitor delivers the initial path at start, and nothing ever changes it.
  `.requiresConnection` and `.satisfied` would each claim an interface exists, so neither is ever
  produced. This is NOT one of the `NWConnection`-style refusals: no transport operation is performed
  and no success is claimed; the value reported is the guest's real state.
* **the demand's own spelling is used where Apple's differs**: `pathUpdateHandler` is declared without
  `@Sendable`. The demanded symbol is `...17pathUpdateHandleryAA0B0VcSgvs`, and `@Sendable` mangles the
  property's function type with a `Y` that name does not carry. The type is ABI-identical either way.
* **absent on purpose**: `currentPath`, `queue`, `init()`, `ethernetChannel`,
  `init(prohibitedInterfaceTypes:)`, `debugDescription`, the `AsyncSequence` half, and `NWPath`'s
  live-path snapshot (`UnsatisfiedReason`, `LinkQuality`, `availableInterfaces`, `isExpensive`,
  `isConstrained`, `supportsIPv4`/`IPv6`/`DNS`, `gateways`, `usesInterfaceType(_:)`) — no demand names
  them and none could be filled with anything but a made-up value.

**The tree side.** `Network.framework` re-exports the dylib as an ordinal, exactly as
`Foundation.framework` re-exports `libswiftFoundation.dylib`: `src/frameworks/Network/CMakeLists.txt`
appends `-Wl,-reexport_library,${CMAKE_SOURCE_DIR}/src/external/swift/libswiftNetwork.dylib` to the
`Network` target (with the same `FATAL_ERROR` guard Foundation uses when the payload file is absent).
Unlike Foundation, which builds explicit `Foundation_x86_64`/`Foundation_i386` targets, `Network` is
one FAT target and `make_fat` appends `-arch i386 -arch x86_64` to one link — measured: ld64 emits
`ignoring file …/libswiftNetwork.dylib, building for macOS-i386 but attempting to link with file built
for macOS-x86_64` and links anyway, so the x86_64 slice re-exports the overlay and the i386 slice does
not, with the framework still universal. That is the behaviour the per-arch split would have produced,
without splitting the target.

## Substitutes for the Xcode 26.3 load-time ladder

Six images this repository did NOT carry are demanded by the guest's Xcode 26.3 load closure, and no
open-source implementation of any of them exists (searched, per name, in `overlays/<Name>/`: the
workspace, swift.org releases, GitHub, and `apple-oss-distributions`, which has no repository for
`libCoreEntitlements`, `RemoteServiceDiscovery` or `OSAnalytics`). Each is a TRUTHFUL substitute: it
exports exactly the names its referrers' bind tables demand, and every answer is a fact about this
guest or an explicit failure -- never a fabricated value and never a `STUB:` string. The per-file
comment in each recipe carries the demand measurement (per dependency field), the client call sites
the shapes come from, and the reasoning for each answer.

| artifact | guest path | demanded by (strong) | what it answers |
| --- | --- | --- | --- |
| `CoreML.framework/Versions/A/CoreML` | `/System/Library/Frameworks/CoreML.framework/Versions/A/CoreML` | DVTSmartSearch, 6 classrefs | model loading, compilation, prediction and multiarray construction answer nil with an `NSError` in Apple's own `MLModelErrorDomain`: this guest has no Core ML runtime |
| `NaturalLanguage.framework/Versions/A/NaturalLanguage` | `/System/Library/Frameworks/NaturalLanguage.framework/Versions/A/NaturalLanguage` | DVTSmartSearch 5, DNTDocumentationSupport 2 | every embedding/tagger factory answers nil (no language assets exist here); `NLLanguageEnglish` = `"en"` and `NLTagSchemeLemma` = `"Lemma"`, their documented values |
| `libswiftNaturalLanguage.dylib` | `/usr/lib/swift/libswiftNaturalLanguage.dylib` | DVTSmartSearch, 4 Swift symbols | the four overlay methods answer absence: `vector(for:)` nil, the two `enumerate...` methods never call their block, `NLTagger.tag(at:unit:scheme:)` `(nil, index..<index)` |
| `substitutes/System/Library/PrivateFrameworks/OSAnalytics.framework/Versions/A/OSAnalytics` | same path in the prefix | XCResultKit 4, IDEFoundation 1 | `+[OSALegacyXform transformURL:options:]` returns `{OSATransformResultError: <NSError>}`: nothing is configured, so nothing is reported and no report is produced |
| `substitutes/System/Library/PrivateFrameworks/RemoteServiceDiscovery.framework/Versions/A/RemoteServiceDiscovery` | same path in the prefix | XCTDaemonControl, 4 functions | no device and no service exist here: NULL, state 0, NULL, and `-1` with `errno = ENOTCONN` |
| `substitutes/usr/lib/libCoreEntitlements.dylib` | `/usr/lib/libCoreEntitlements.dylib` | DVTPortal, 6 names | there is no entitlement engine here: the three operations answer an explicit "not implemented in this guest" `CE_Error_t` (never `kCENoError`), `CECRuntime` is NULL, and `kCENoError` is the `"no error"` CFStringRef its name claims |

Two payload shapes carry them: the three at the payload root ride the existing `libswift*.dylib` and
`*.framework` globs, and the three whose guest path is neither a `/System/Library/Frameworks` path
nor a `/usr/lib/swift` dylib live under `substitutes/`, whose layout mirrors the guest tree (one
recursive glob in the superproject's `CMakeLists.txt` stages and declares them).

All six are built for `x86_64-apple-macosx26.0` by `overlays/<Name>/build.sh` (and
`overlays/NaturalLanguage/build-overlay.sh` for the Swift half), which need only the environment the
sibling overlay recipes already document. Each was verified at four points: the deployed export trie
carries every demanded name (`scripts/rung-driver.py verify --component ...` reports 0 absent and
analyzer MISS 0), the four sha-chain legs are byte-identical, the recipe rebuilds to the same bytes
from a second checkout directory, and the guest's own loader `dlopen`s each image by its guest path.

## A private framework the closure demands: `ArgumentParserInternal` (added 2026-10-15)

Xcode 26.3's new build system lives in the plug-in `com.apple.dt.IDEXCBuildSupportCore`. Its binary
cannot load without

    /System/Library/PrivateFrameworks/ArgumentParserInternal.framework/Versions/A/ArgumentParserInternal

because `SwiftBuild.framework/…/SWBBuildService.bundle/Contents/Frameworks/SWBUtil.framework/Versions/A/SWBUtil`
hard-links that install name and binds 65 strong eager symbols from it (`ArgumentParserInternal.Option`,
`.Flag`, `.ArgumentHelp`, `.ParsableCommand`, the protocol requirement descriptors, …). While the image
is absent the whole plug-in is refused with `Reason: image not found`, the extension
`Xcode.IDEFoundation.BuildSystemServiceProvider.XCBuild` never faults, and `xcodebuild` reports the new
build system as unavailable.

It is supplied BY SOURCE, not by a substitute: `overlays/ArgumentParserInternal/build.sh` fetches
[apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) at a pinned commit
(`011f0c765fb46d9cac61bca19be0527e99c98c8b`, tag `1.5.1`) and builds Apple's own implementation under the
module name Apple's image uses, linked at the demanded install name. The release was chosen by
measurement against the SDK's `ArgumentParserInternal.tbd` (707 names, the contract of record): 1.5.0 and
1.5.1 reproduce 706 of them — including every resilient protocol requirement descriptor and every `vpMV`
field descriptor — while 1.3.1 gives 682, 1.4.0 689, 1.7.x 698 and 1.8.x 698 with ~100 extra names. The
one tbd name no upstream release can produce is the `_superCommandName` memberwise initializer with its
pre-`aliases` parameter list, which Apple's internal copy froze at an older ABI; it is not part of the
plug-in's demand. All 65 demanded names are exported by the built image, and the file is deployed at the
private-framework path by the superproject's `private-frameworks/*.framework` manifest glob — the third
payload shape, since neither the `libswift*.dylib` glob (`/usr/lib/swift`) nor the `*.framework` glob
(`/System/Library/Frameworks`) can express it.

## The last two names of the ladder: Accelerate and SoftLinking

Two further images the closure still demands are NOT substitutes for a missing implementation: both
are real libraries built by their own recipes, and neither is deployed or guest-verified yet.

| artifact | guest path | demanded by (strong) | what it is |
| --- | --- | --- | --- |
| `libswiftAccelerate.dylib` | `/usr/lib/swift/libswiftAccelerate.dylib` | DVTSmartSearch, 4 Swift symbols (`BNNS.Shape.vector`, `BNNS.Shape` metadata, `Float: BNNSScalar`, `BNNSNDArrayDescriptor.init(data:shape:)`) | a build of the module's BNNS subset, declared from the SDK's public `Accelerate.swiftinterface` and Apple's published `bnns_constants.h`/`bnns_structures.h`; the open-source overlay (`swiftlang/swift`, `stdlib/public/Darwin/Accelerate`, last present at swift-5.2-RELEASE) does not declare this API. 61 exports, every one of them inside Apple's x86_64-macos symbol set for this install name; only `.vector` is declared, and every other member fails at load. Its only dependencies are libswiftCore and libSystem. |
| `substitutes/System/Library/PrivateFrameworks/SoftLinking.framework/Versions/A/SoftLinking` | same path in the prefix | IDEFoundation, 1 function (`__sl_dlopen`) | a real implementation of the two entry points Apple's tbd exports (`__sl_dlopen`, `__sl_dlopen_audited`): it reads the caller's NULL-terminated path array, parses the `softlink:<flag>:path:<path>` directive the compiler records in `__TEXT,__dlopen_cstrs` (ld64's own offsets; the flag token is not interpreted because nothing documents it), dlopens the path with `RTLD_LAZY|RTLD_LOCAL`, and reports the failure the way the caller expects -- a malloc'd message in its out-parameter, which the caller frees or prints. Its only dependency is libSystem. |

Both grew out of the wave sweep's two remaining PAYLOAD rows, and both are reproducible: each recipe
was built from two different checkout directories and the two files are byte-identical.

## StorageKit private-framework provider

`overlays/StorageKit/` supplies the measured subset of Apple's private
`/System/Library/PrivateFrameworks/StorageKit.framework/Versions/A/StorageKit`
that CoreDevice and the Xcode build-service load path bind. It is a source
implementation, not an empty class-name shim: the image exports the demanded
classes and selectors, attach runs the real `/usr/bin/hdiutil` FUSE backend
against the HFS+ `DeveloperDiskImage.dmg`, and `SKManager` exposes the mounted
disk only while the host mount table still contains its mount.

Build and install are deliberately split:

- The only supported provider build entrypoint is
  `overlays/StorageKit/build.sh` (with `SWIFT_TOOLCHAIN`, `DARLING_SDK`,
  `DARLING_LD`, `DARLING_LIBSYSTEM`, `DARLING_ROOT`). It writes
  `substitutes/System/Library/PrivateFrameworks/StorageKit.framework/Versions/A/StorageKit`.
- `overlays/build.sh` and `overlays/build-arch.sh` do not call this recipe, and
  `swift/CMakeLists.txt` has no StorageKit target. The superproject's rootless
  staging glob (`CMakeLists.txt`, `src/external/swift/substitutes/*`) copies a
  provider file if one is already present under `substitutes/`; it does not
  build it.
- A fresh checkout therefore has no StorageKit image until the individual
  recipe is run. Reproducing the provider from a clean checkout, and deploying
  it to both prefix roots, is not established by a manual binary install and
  must not be reported as canonical CMake/install coverage.
- The hdiutil backend is the existing `darling-dmg` CMake target
  `hdiutil` (`add_darling_executable`, installed under
  `libexec/darling/usr/bin`). That target is independent of the StorageKit
  recipe.

Known boundaries: the provider is an HFS+ hdiutil/FUSE implementation, not
APFS, arbitrary-UDIF, or full CoreDevice StorageKit support. It checks the
kernel mount table before claiming a detach, resolves guest mount identity
through Darling's `__darling_vchroot_expand` API by exact host path, and
reconciles stale manager attachments when the mount has disappeared. A failed mount-directory cleanup
is reported as a warning but does not turn a confirmed unmount into a fake live
mount, and the directory is never recursively removed. The iOS application
still stops at the separate AppServerSupport load prerequisite.
