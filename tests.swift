import Foundation
let wk = #"{"kind":"weekly_all","group":"weekly","percent":27,"resets_at":"2026-11-18T16:00:00.431636+00:00","scope":null,"is_active":true}"#
let fable = #"{"kind":"weekly_scoped","group":"weekly","percent":15,"resets_at":"2026-11-18T16:00:00.431775+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}"#
let session = #"{"kind":"session","group":"session","percent":40,"resets_at":"2026-11-12T12:00:00.1+00:00","scope":null}"#
let fh = #""five_hour":{"utilization":40,"resets_at":"2026-11-12T12:00:00.123456+00:00"}"#
let badDate = #"{"kind":"weekly_all","group":"weekly","percent":5,"resets_at":"not a date"}"#
func names(_ json: String) throws -> [String] { try UsageAPI.parse(Data(json.utf8)).map(\.name) }
var fails = 0
func check(_ label: String, _ json: String, _ want: [String]) {
    let got = (try? names(json)) ?? ["<decode error>"]
    let ok = got == want; if !ok { fails += 1 }
    print(ok ? "PASS" : "FAIL", label, got)
}
@main struct T { static func main() async {
    check("your shape: five_hour null", #"{"five_hour":null,"limits":[\#(wk),\#(fable)]}"#, ["Weekly · all models", "Weekly · Fable"])
    check("five_hour key absent, no limits", #"{}"#, [])
    check("five_hour absent, weekly only", #"{"limits":[\#(wk)]}"#, ["Weekly · all models"])
    check("old style: five_hour only", #"{\#(fh)}"#, ["5-hour"])
    check("five_hour + weekly", #"{\#(fh),"limits":[\#(wk)]}"#, ["5-hour", "Weekly · all models"])
    check("5h in both places: no duplicate", #"{\#(fh),"limits":[\#(session),\#(wk)]}"#, ["5-hour", "Weekly · all models"])
    check("bad date skipped", #"{"limits":[\#(badDate),\#(wk)]}"#, ["Weekly · all models"])
    check("limits null", #"{"five_hour":null,"limits":null}"#, [])

    func expect(_ label: String, _ ok: Bool) { if !ok { fails += 1 }; print(ok ? "PASS" : "FAIL", label) }
    let formula = """
      url "https://github.com/RoryDotGG/QuotaBar.git",
          tag:      "v1.10.2",
          revision: "8e9e001563ec26da33a49a0b1f88a6b30450381d"
    """
    expect("formula version parsed", Updates.formulaVersion(formula) == "1.10.2")
    expect("formula without tag -> nil", Updates.formulaVersion(#"head "x", branch: "main""#) == nil)
    expect("1.10.0 newer than 1.9.0 (not string order)", Updates.isNewer("1.10.0", than: "1.9.0"))
    expect("1.3.1 newer than 1.3.0", Updates.isNewer("1.3.1", than: "1.3.0"))
    expect("same version is not newer", !Updates.isNewer("1.3.0", than: "1.3.0"))
    expect("older is not newer", !Updates.isNewer("1.2.9", than: "1.3.0"))
    expect("1.3 equals 1.3.0", !Updates.isNewer("1.3", than: "1.3.0") && !Updates.isNewer("1.3.0", than: "1.3"))
    expect("2.0 newer than 1.99.99", Updates.isNewer("2.0", than: "1.99.99"))

    // Learning: two weeks of 2%/hour on weekdays 9-17 only (80% a week), read every 5 minutes.
    let mon = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2))!  // Monday, local midnight
    func working(_ t: Date) -> Bool {
        let c = Calendar.current.dateComponents([.weekday, .hour], from: t)
        return (2...6).contains(c.weekday!) && (9..<17).contains(c.hour!)
    }
    func weekly(_ start: Date, _ used: Double) -> Limit {
        Limit(id: "weekly_all-", name: "Weekly", used: used, resetsAt: start + 7 * 86400, length: 7 * 86400)
    }
    var pat = Patterns()
    for week in 0..<2 {
        let start = mon + Double(week) * 7 * 86400
        var used = 0.0
        for step in 0...(7 * 288) {
            let t = start + Double(step) * 300
            if step > 0, working(t - 300) { used += 2.0 / 12 }
            pat.record([weekly(start, used)], at: t)
        }
    }
    let week3 = mon + 14 * 86400, monEvening = week3 + 17 * 3600
    expect("learned after two weeks", pat.learnedHours("weekly_all-") >= Patterns.learnedHours)
    let usual = pat.forecast(weekly(week3, 16), now: monEvening)  // a normal Monday so far
    expect("usual week: lasts, ~80% at reset (got \(usual.projected))", usual.learned && usual.runsOut == nil && abs(usual.projected - 80) < 1)
    expect("straight line would wrongly run out", weekly(week3, 16).linear(monEvening).runsOut != nil)
    let heavy = pat.forecast(weekly(week3, 24), now: monEvening)  // 1.5x a usual Monday
    let out = heavy.runsOut.map { Calendar.current.dateComponents([.weekday, .hour, .minute], from: $0) }
    expect("heavy week: runs out Fri ~10:20 (got \(String(describing: heavy.runsOut)))",
           out?.weekday == 6 && out?.hour == 10 && abs((out?.minute ?? 0) - 20) <= 1)
    var fresh = Patterns()
    fresh.record([weekly(week3, 5)], at: week3 + 3600)
    expect("untrained falls back to straight line", !fresh.forecast(weekly(week3, 16), now: monEvening).learned)

    do {
        let live = try await UsageAPI.fetch()
        let ok = !live.isEmpty && !live.contains { $0.length < 86400 }
        if !ok { fails += 1 }
        print(ok ? "PASS" : "FAIL", "live account: no 5h row", live.map(\.name))
    } catch { fails += 1; print("FAIL live", error) }
    print(fails == 0 ? "ALL PASS" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
}}
