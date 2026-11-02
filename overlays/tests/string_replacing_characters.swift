// StringProtocol replacement through the public Foundation entry point.
import Foundation

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok:" : "FAIL:", label)
    if !condition { failures += 1 }
}

@inline(never)
func replace<S: StringProtocol, T: StringProtocol, R: RangeExpression>(
    _ source: S, _ range: R, _ replacement: T
) -> String where R.Bound == String.Index {
    source.replacingCharacters(in: range, with: replacement)
}

let ascii = "abc"
let middle = ascii.index(after: ascii.startIndex)
check(replace(ascii, middle..<ascii.index(after: middle), "XYZ") == "aXYZc", "String receiver")

// Nonzero base indices, a supplementary scalar and a combining sequence must
// survive replacement without translating indices through a copied String.
let storage = "xxA🦀e\u{301}Zyy"
let slice = storage.dropFirst(2).dropLast(2)
let crab = slice.index(after: slice.startIndex)
let afterCrab = slice.index(after: crab)
let replacement = "xx🐬yy".dropFirst(2).dropLast(2)
check(replace(slice, crab..<afterCrab, replacement) == "A🐬e\u{301}Z", "Substring receiver and replacement")
check(replace(slice, crab..<afterCrab, "") == "Ae\u{301}Z", "deletion preserves combining sequence")
check(replace(slice, slice.startIndex...slice.index(before: slice.endIndex), "Q") == "Q", "closed range includes final character")
check(replace(slice, crab..., "X") == "AX", "partial range from")
check(replace(slice, ...crab, "X") == "Xe\u{301}Z", "partial range through supplementary scalar")
check(replace(slice, ..<crab, "X") == "X🦀e\u{301}Z", "partial range up to")
check(replace(slice, slice.endIndex..<slice.endIndex, "!") == "A🦀e\u{301}Z!", "empty range at end inserts")
let empty = storage[storage.endIndex..<storage.endIndex]
check(replace(empty, empty.startIndex..<empty.endIndex, replacement) == "🐬", "empty nonzero-based substring")
check(storage == "xxA🦀e\u{301}Zyy", "receiver storage remains unchanged")

print("REPLACING_CHARACTERS failures=\(failures)")
if failures != 0 { exit(1) }
print("REPLACING_CHARACTERS_OK")
