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
    do {
        let live = try await UsageAPI.fetch()
        let ok = !live.isEmpty && !live.contains { $0.length < 86400 }
        if !ok { fails += 1 }
        print(ok ? "PASS" : "FAIL", "live account: no 5h row", live.map(\.name))
    } catch { fails += 1; print("FAIL live", error) }
    print(fails == 0 ? "ALL PASS" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
}}
