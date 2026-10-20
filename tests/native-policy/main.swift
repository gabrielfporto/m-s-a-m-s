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

// Exercise both callback orders observed around the system authentication UI.
for callbackBeforeActivation in [true, false] {
    var lifecycle = DeviceUnlockLifecycle()
    check(!lifecycle.consumeAutomaticAttempt(), "do not prompt while inactive")
    lifecycle.becameActive()
    check(lifecycle.consumeAutomaticAttempt(), "one automatic unlock on launch")
    let attemptEpoch = lifecycle.epoch
    lifecycle.resignedActive()
    var unlocked = false
    if callbackBeforeActivation {
        unlocked = lifecycle.acceptsAuthentication(from: attemptEpoch)
        check(!lifecycle.canReveal(unlocked: unlocked), "keep content covered until scene activation")
    }
    lifecycle.becameActive()
    if !callbackBeforeActivation { unlocked = lifecycle.acceptsAuthentication(from: attemptEpoch) }
    check(lifecycle.canReveal(unlocked: unlocked), "recognized Face ID must release the cover in either callback order")
    check(!lifecycle.consumeAutomaticAttempt(), "activation after Face ID must not request another authentication")
    lifecycle.enteredBackground()
    check(!lifecycle.acceptsAuthentication(from: attemptEpoch), "a late success cannot unlock a new background session")
    check(!lifecycle.canReveal(unlocked: true), "background content stays protected")
    lifecycle.becameActive()
    check(lifecycle.consumeAutomaticAttempt(), "returning from real background starts a new unlock cycle")
}
var cancelled = DeviceUnlockLifecycle()
cancelled.becameActive(); check(cancelled.consumeAutomaticAttempt(), "initial prompt")
cancelled.resignedActive(); cancelled.becameActive()
check(!cancelled.canReveal(unlocked: false), "failed authentication keeps the cover")
check(!cancelled.consumeAutomaticAttempt(), "cancel must leave an explicit retry button, not an automatic loop")
print("Face ID scene ordering, successful unlock, cancellation and background regression checks passed.")

var temporary = DeviceUnlockLifecycle()
temporary.becameActive(); _ = temporary.consumeAutomaticAttempt()
let temporaryEpoch = temporary.epoch
temporary.resignedActive(); temporary.becameActive()
check(temporary.epoch == temporaryEpoch, "Notification Center must not end the unlocked session")
check(temporary.canReveal(unlocked: true), "temporary overlays return directly to the app")
check(!temporary.consumeAutomaticAttempt(), "temporary overlays do not request Face ID again")
for (kind, page) in DevicePolicy.destinations {
    let row: [String: Any] = ["id":"ma-\(kind)-2026-10-20","kind":kind,"date":"2026-10-20","hour":9,"page":page]
    let reminders = DevicePolicy.reminders([row], now: now, calendar: calendar)
    check(reminders.count == 1, "every configured kind has a native destination")
    check(!reminders[0].body.contains("R$"), "all notification kinds keep amounts private")
}
print("Temporary overlays preserve unlock; expanded reminder kinds are validated.")
