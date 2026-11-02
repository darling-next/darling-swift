// NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(_:), the pre-secure-coding top-level
// decode entry point Prefire 5.6.1 and Sourcery 2.3.0 bind eagerly at launch. Runs under
// Darling against the rebuilt Foundation overlay and the restored native Foundation
// selector; it must not be satisfied by a stub symbol.
import Foundation

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok:" : "FAIL:", label)
    if !condition { failures += 1 }
}

// The authoritative Foundation error contract: NSCocoaErrorDomain 4865 for a missing
// root object (NSCoderValueNotFoundError) and 4864 for unreadable/corrupt archives
// (NSCoderReadCorruptError). The Swift `throws` surface must report these, not abort.
func checkCocoaError(_ label: String, code: Int, _ body: () throws -> Any?) {
    do {
        let value = try body()
        check(false, "\(label) must throw, returned \(String(describing: value))")
    } catch let error as NSError {
        check(
            error.domain == NSCocoaErrorDomain && error.code == code,
            "\(label) reports Cocoa \(code) (\(error.domain) \(error.code))"
        )
    } catch {
        check(false, "\(label) reported a non-NSError \(error)")
    }
}

// Numeric root: the round trip every keyed archive performs.
let number = NSNumber(value: 42)
let numberData = NSKeyedArchiver.archivedData(withRootObject: number)
do {
    let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(numberData)
    check((decoded as? NSNumber) == number, "unarchiveTopLevelObjectWithData round-trips a numeric root")
} catch {
    check(false, "numeric-root decode threw \(error)")
}

// String and dictionary roots take the archive's container/object paths.
let stringData = NSKeyedArchiver.archivedData(withRootObject: "value" as NSString)
do {
    let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(stringData)
    check((decoded as? NSString) == "value", "unarchiveTopLevelObjectWithData decodes a string root")
} catch {
    check(false, "string-root decode threw \(error)")
}

let dictionary: [String: String] = ["key": "value"]
let dictionaryData = NSKeyedArchiver.archivedData(withRootObject: dictionary)
do {
    let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(dictionaryData)
    check((decoded as? [String: String]) == dictionary, "unarchiveTopLevelObjectWithData decodes a dictionary root")
} catch {
    check(false, "dictionary-root decode threw \(error)")
}

// A valid archive with no root key exercises the coder's missing-root error path.
let noRootData = NSMutableData(capacity: 0)!
let archiver = NSKeyedArchiver(forWritingWith: noRootData)
archiver.encode("value" as NSString, forKey: "other")
archiver.finishEncoding()
checkCocoaError("archive without a root key", code: 4865) {
    try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(noRootData as Data)
}

// Unreadable bytes must throw the corrupt-archive error instead of aborting through an
// Objective-C exception or a non-failable initializer.
checkCocoaError("unreadable archive bytes", code: 4864) {
    try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(Data([0xFF, 0x00, 0x01]))
}

// A property list that claims to be a keyed archive but has no $top/$objects reaches the
// coder's NSInvalidUnarchiveOperationException path; the native entry point converts it.
let corruptPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>$version</key><integer>100000</integer></dict></plist>
"""
checkCocoaError("corrupt keyed-archive property list", code: 4864) {
    try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(Data(corruptPlist.utf8))
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
if failures != 0 { exit(1) }
