// TimeZone through the Foundation overlay, under Darling.
import Foundation

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok:" : "FAIL:", label)
    if !condition { failures += 1 }
}

// 2021-01-15 12:00:00 UTC and 2021-07-15 12:00:00 UTC
let winter = Date(timeIntervalSince1970: 1610712000)
let summer = Date(timeIntervalSince1970: 1626350400)

if let newYork = TimeZone(identifier: "America/New_York") {
    check(newYork.identifier == "America/New_York", "init(identifier:)")
    check(newYork.secondsFromGMT(for: winter) == -5 * 3600, "secondsFromGMT(for:) winter (\(newYork.secondsFromGMT(for: winter)))")
    check(newYork.secondsFromGMT(for: summer) == -4 * 3600, "secondsFromGMT(for:) summer (\(newYork.secondsFromGMT(for: summer)))")
    check(!newYork.isDaylightSavingTime(for: winter) && newYork.isDaylightSavingTime(for: summer), "isDaylightSavingTime(for:)")
    check(newYork.daylightSavingTimeOffset(for: summer) == 3600, "daylightSavingTimeOffset(for:)")
    // Darling's -abbreviationForDate: can give the abbreviation for another date, so compare with NSTimeZone.
    let abbreviation = newYork.abbreviation(for: winter)
    check(abbreviation != nil && abbreviation == (newYork as NSTimeZone).abbreviation(for: winter),
          "abbreviation(for:) matches NSTimeZone (\(String(describing: abbreviation)))")
    if let transition = newYork.nextDaylightSavingTimeTransition(after: winter) {
        check(transition > winter && transition < summer, "nextDaylightSavingTimeTransition(after:) (\(transition))")
    } else {
        check(false, "nextDaylightSavingTimeTransition(after:)")
    }
    check(newYork == TimeZone(identifier: "America/New_York")! && newYork != TimeZone(identifier: "Europe/Paris")!, "equality")
    check(Set([newYork, TimeZone(identifier: "America/New_York")!, TimeZone(identifier: "Asia/Tokyo")!]).count == 2, "Hashable")
    let ns = newYork as NSTimeZone
    check(ns.name() == "America/New_York", "TimeZone bridges to NSTimeZone")
    check((ns as TimeZone) == newYork, "NSTimeZone bridges back")
    check(newYork.description == "America/New_York (fixed)", "description (\(newYork.description))")
} else {
    check(false, "init(identifier:) America/New_York")
}
check(TimeZone(identifier: "Not/AZone") == nil, "unknown identifier gives nil")

if let plusTwo = TimeZone(secondsFromGMT: 7200) {
    check(plusTwo.secondsFromGMT(for: winter) == 7200 && plusTwo.secondsFromGMT(for: summer) == 7200, "init(secondsFromGMT:) (\(plusTwo.identifier))")
} else {
    check(false, "init(secondsFromGMT:)")
}
check(TimeZone(abbreviation: "GMT")?.secondsFromGMT(for: winter) == 0, "init(abbreviation:)")

let current = TimeZone.current
check(current.identifier == ((NSTimeZone.default() as NSTimeZone?)?.name() ?? ""), "current matches +[NSTimeZone defaultTimeZone] (\(current.identifier))")
check(current.secondsFromGMT() == ((NSTimeZone.default() as NSTimeZone?)?.secondsFromGMT() ?? -1), "current secondsFromGMT()")
check(NSTimeZone.system().identifier == ((NSTimeZone.system() as NSTimeZone?)?.name() ?? ""), "systemTimeZone bridges without touching +localTimeZone")
// autoupdatingCurrent works with TZ unset, valid or unresolvable. Darling's +localTimeZone crashes without TZ, so it is
// only queried when TZ is set.
let autoupdating = TimeZone.autoupdatingCurrent
check(autoupdating == TimeZone.autoupdatingCurrent && autoupdating != current, "autoupdatingCurrent equality")
let localZone = getenv("TZ") != nil ? NSTimeZone.local() as NSTimeZone? : nil
check(autoupdating.identifier == (localZone?.name() ?? current.identifier), "autoupdatingCurrent identifier (\(autoupdating.identifier))")
if localZone != nil {
    check((autoupdating as NSTimeZone as TimeZone) == autoupdating, "autoupdatingCurrent bridges round trip")
}
// With a valid TZ, Darling's +defaultTimeZone can be the +localTimeZone instance itself, which bridging can't tell apart.
if localZone == nil || (NSTimeZone.default() as NSTimeZone?) !== localZone {
    check(NSTimeZone.default() != autoupdating, "+defaultTimeZone bridges as a fixed time zone")
}

check(TimeZone.knownTimeZoneIdentifiers.contains("Europe/Paris"), "knownTimeZoneIdentifiers (\(TimeZone.knownTimeZoneIdentifiers.count))")
check(!TimeZone.abbreviationDictionary.isEmpty, "abbreviationDictionary (\(TimeZone.abbreviationDictionary.count))")

// Without a +localTimeZone zone, autoupdatingCurrent follows +setDefaultTimeZone:.
if localZone == nil, let tokyo = NSTimeZone(name: "Asia/Tokyo"), let previousDefault = NSTimeZone.default() {
    NSTimeZone.setDefault(tokyo as TimeZone)
    check(TimeZone.autoupdatingCurrent.identifier == "Asia/Tokyo", "autoupdatingCurrent follows setDefault (\(TimeZone.autoupdatingCurrent.identifier))")
    NSTimeZone.setDefault(previousDefault)
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
