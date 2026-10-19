import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
check(DevicePolicy.acceptsOrigin(scheme: "https", host: DevicePolicy.host, port: 443, mainFrame: true), "first-party bridge")
for (scheme, host, port, main) in [("http",DevicePolicy.host,80,true),("https","evil.example",443,true),("https",DevicePolicy.host,444,true),("https",DevicePolicy.host,443,false)] {
    check(!DevicePolicy.acceptsOrigin(scheme: scheme, host: host, port: port, mainFrame: main), "foreign origins and subframes must not reach native APIs")
}
var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let now = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!
let valid: [String: Any] = ["id":"ma-bills-2026-10-20","kind":"bills","date":"2026-10-20","hour":9,"page":"Cartões"]
let jobs = DevicePolicy.reminders([valid, valid], now: now, calendar: calendar)
check(jobs.count == 1, "duplicate notifications")
check(jobs[0].components.date! > now, "future local calendar trigger")
check(!jobs[0].body.contains("R$"), "no financial values in lock-screen text")
for change in [["date":"2026-10-17"],["date":"2026-11-31"],["date":"2027-01-01"],["page":"Perfil"],["kind":"unknown"],["hour":3],["id":"foreign-id"]] as [[String: Any]] {
    check(DevicePolicy.reminders([valid.merging(change){_,v in v}], now: now, calendar: calendar).isEmpty, "invalid, stale or foreign job")
}
check(DevicePolicy.reminders(["invalid"], now: now).isEmpty, "malformed bridge payload")
print("Native origin, notification privacy, deduplication, date and destination checks passed.")
