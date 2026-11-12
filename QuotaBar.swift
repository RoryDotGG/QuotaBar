// QuotaBar: Claude plan usage in the macOS menu bar.
// Reads Claude Code's sign-in from the keychain and polls the unofficial usage
// endpoint every 5 minutes (backing off to 30 on 429). When the token expires it asks the CLI to renew it
// (`claude auth status`), so the refresh token is only ever rotated by the CLI.
import ServiceManagement
import SwiftUI

// MARK: - Model

struct Limit: Identifiable, Sendable, Codable {
    let id: String
    let name: String
    let used: Double  // 0...100
    let resetsAt: Date
    let length: TimeInterval

    var start: Date { resetsAt - length }
    func elapsed(_ now: Date) -> Double { min(max(now.timeIntervalSince(start) / length, 0), 1) }
    // ponytail: linear pace since window start; noisy in the first day of a week
    func rate(_ now: Date) -> Double { used / max(now.timeIntervalSince(start), 60) }
    func projected(_ now: Date) -> Double { used + rate(now) * resetsAt.timeIntervalSince(now) }
    func runsOut(_ now: Date) -> Date? {
        guard rate(now) > 0, projected(now) >= 100 else { return nil }
        return now + (100 - used) / rate(now)
    }
}

enum FetchError: Error {
    case noCredentials, tokenExpired, cannotRenew, badResponse(Int)

    var message: String {
        switch self {
        case .noCredentials: "No Claude Code sign-in found. Run `claude auth login` in Terminal."
        case .tokenExpired, .cannotRenew: "Sign-in expired and couldn't be renewed. Run `claude auth login` in Terminal."
        case .badResponse(let code): "Usage request failed (HTTP \(code))."
        }
    }
}

// MARK: - Fetching

enum UsageAPI {
    private struct Resp: Decodable {
        struct Window: Decodable { let utilization: Double; let resets_at: String }
        struct Entry: Decodable {
            struct Scope: Decodable { struct Model: Decodable { let display_name: String? }; let model: Model? }
            let kind: String
            let group: String?
            let percent: Double
            let resets_at: String
            let scope: Scope?
        }
        let five_hour: Window?
        let limits: [Entry]?
    }

    static func fetch() async throws -> [Limit] {
        do {
            return try await fetchOnce()
        } catch FetchError.tokenExpired {
            // The desktop app doesn't renew this token; the CLI does, without a model call.
            try renewSignIn()
            return try await fetchOnce()
        }
    }

    private static func renewSignIn() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let cli = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw FetchError.cannotRenew
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["auth", "status"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        let deadline = Date() + 20
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if p.isRunning { p.terminate(); throw FetchError.cannotRenew }
    }

    private static func fetchOnce() async throws -> [Limit] {
        let token = try readToken()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw code == 401 ? FetchError.tokenExpired : FetchError.badResponse(code) }
        return try parse(data)
    }

    /// Any window can be absent or null; some accounts (e.g. Ultra) have no 5-hour limit at all.
    static func parse(_ data: Data) throws -> [Limit] {
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        var out: [Limit] = []
        for e in resp.limits ?? [] {
            guard let r = parseDate(e.resets_at) else { continue }
            let weekly = e.group == "weekly"
            let model = e.scope?.model?.display_name
            let name: String
            if weekly {
                name = e.kind == "weekly_all" ? "Weekly · all models" : "Weekly · \(model ?? e.kind)"
            } else {
                name = model.map { "5-hour · \($0)" } ?? "5-hour"
            }
            out.append(Limit(id: "\(e.kind)-\(model ?? "")", name: name, used: e.percent, resetsAt: r,
                             length: weekly ? 7 * 86400 : 5 * 3600))
        }
        // Older field; use it only if `limits` didn't already list a 5-hour window.
        if let w = resp.five_hour, let r = parseDate(w.resets_at), !out.contains(where: { $0.length < 86400 }) {
            out.insert(Limit(id: "five_hour", name: "5-hour", used: w.utilization, resetsAt: r, length: 5 * 3600), at: 0)
        }
        return out
    }

    // /usr/bin/security already has access to this item, so no keychain prompt.
    private static func readToken() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw FetchError.noCredentials }
        let expiresMs = (oauth["expiresAt"] as? Double) ?? 0
        guard expiresMs / 1000 > Date().timeIntervalSince1970 + 30 else { throw FetchError.tokenExpired }
        return token
    }

    // API sends microseconds ("…00.431636+00:00"); ISO8601DateFormatter only takes up to 3 digits.
    private static func parseDate(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

// MARK: - Install

/// Homebrew installs live in a versioned Cellar folder that `brew upgrade` deletes, so
/// anything that stores our path (login items, Finder aliases) breaks on upgrade.
/// For Homebrew installs: start at login via `brew services` (fixed opt path), and
/// repair the ~/Applications alias on every launch. Checkout builds use SMAppService.
enum Install {
    static let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()

    /// e.g. /opt/homebrew for /opt/homebrew/Cellar/quotabar/1.1.0/QuotaBar.app
    static let brewPrefix: String? = {
        let path = bundleURL.path
        guard let r = path.range(of: "/Cellar/quotabar/") else { return nil }
        return String(path[..<r.lowerBound])
    }()

    static var isHomebrew: Bool { brewPrefix != nil }

    // Homebrew 7 labels services sh.brew.<name>; older versions used homebrew.mxcl.<name>.
    private static var agentPlists: [String] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        return ["sh.brew.quotabar.plist", "homebrew.mxcl.quotabar.plist"].map { dir.appendingPathComponent($0).path }
    }

    static var startsAtLogin: Bool {
        isHomebrew ? agentPlists.contains(where: FileManager.default.fileExists)
                   : SMAppService.mainApp.status == .enabled
    }

    /// Blocking (brew takes a few seconds); call off the main actor.
    static func setStartsAtLogin(_ on: Bool) {
        guard let prefix = brewPrefix else {
            try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            return
        }
        // `restart`, not `start`: start fails ("Bootstrap failed: 5") if the job is
        // already loaded. Either way a fresh copy launches and replaces this one.
        brewServices(prefix, on ? "restart" : "stop")
    }

    private static func brewServices(_ prefix: String, _ verb: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "\(prefix)/bin/brew")
        p.arguments = ["services", verb, "quotabar"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    /// `brew upgrade` deletes our Cellar folder but doesn't restart us. When that happens,
    /// open the new version from the stable opt path; it quits this copy on launch.
    private static var relaunched = false
    static func relaunchIfUpgraded() {
        guard let prefix = brewPrefix, !relaunched,
              !FileManager.default.fileExists(atPath: bundleURL.path) else { return }
        let next = "\(prefix)/opt/quotabar/QuotaBar.app"
        guard FileManager.default.fileExists(atPath: next) else { return }
        relaunched = true
        // With the service on, restart it so its `open -W` tracks the new copy.
        if startsAtLogin {
            Thread.detachNewThread { brewServices(prefix, "restart") }
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", next]
        try? p.run()
    }

    static func onLaunch() {
        quitOlderCopies()
        guard isHomebrew else { return }
        // A login item from 1.0.x points at a Cellar folder that no longer exists.
        if SMAppService.mainApp.status != .notRegistered { try? SMAppService.mainApp.unregister() }
        repairAlias()
    }

    /// Newest launch wins, so an upgrade or a second start never leaves two in the menu bar.
    private static func quitOlderCopies() {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.quotabar")
        where app.processIdentifier != me {
            app.terminate()
        }
    }

    /// Keeps ~/Applications/QuotaBar.app (a Finder alias, so launchers index it) pointing
    /// at this copy. Never replaces anything that isn't already an alias.
    private static func repairAlias() {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let alias = dir.appendingPathComponent("QuotaBar.app")
        if fm.fileExists(atPath: alias.path) {
            let isAlias = (try? alias.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile ?? false
            guard isAlias else { return }
            if (try? URL(resolvingAliasFileAt: alias))?.resolvingSymlinksInPath() == bundleURL { return }
            try? fm.removeItem(at: alias)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? bundleURL.bookmarkData(options: .suitableForBookmarkFile,
                                                  includingResourceValuesForKeys: nil, relativeTo: nil) {
            try? URL.writeBookmarkData(data, to: alias)
        }
    }
}

// MARK: - State

@MainActor
final class UsageStore: ObservableObject {
    @Published var limits: [Limit] = []
    @Published var error: String?
    @Published var updatedAt: Date?
    @Published var loading = false
    @Published var launchAtLogin = Install.startsAtLogin

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on  // optimistic; corrected once brew/SMAppService returns
        Task.detached {
            Install.setStartsAtLogin(on)
            await MainActor.run { self.refreshLoginStatus() }
        }
    }

    /// Re-read in case it was changed elsewhere (System Settings, `brew services`).
    func refreshLoginStatus() { launchAtLogin = Install.startsAtLogin }

    // The endpoint returns 429 (with retry-after: 0) if polled hard; weekly numbers move slowly.
    private static let normalInterval: TimeInterval = 300
    private static let maxInterval: TimeInterval = 1800
    private static let manualMinGap: TimeInterval = 60

    // Saved across launches so a relaunch neither loses the numbers nor re-hits the endpoint.
    private struct Saved: Codable {
        var limits: [Limit]
        var updatedAt: Date?
        var lastAttempt: Date
        var nextAllowed: Date
        var interval: TimeInterval
    }
    private var lastAttempt = Date.distantPast
    private var nextAllowed = Date.distantPast
    private var interval = normalInterval

    init() {
        Install.onLaunch()
        if let data = UserDefaults.standard.data(forKey: "saved"),
           let s = try? JSONDecoder().decode(Saved.self, from: data) {
            (limits, updatedAt, lastAttempt, nextAllowed, interval) =
                (s.limits, s.updatedAt, s.lastAttempt, s.nextAllowed, s.interval)
            if nextAllowed > Date() { error = Self.pausedMessage(until: nextAllowed) }
        }
        Task {
            while !Task.isCancelled {
                Install.relaunchIfUpgraded()
                await refresh(manual: false)
                try? await Task.sleep(for: .seconds(30))  // cheap wake-up; refresh decides whether to call
            }
        }
    }

    func refresh(manual: Bool) async {
        let now = Date()
        let gap = manual ? Self.manualMinGap : interval
        guard !loading, now >= nextAllowed, now.timeIntervalSince(lastAttempt) >= gap else { return }
        loading = true
        lastAttempt = now
        defer { loading = false; save() }
        do {
            limits = try await UsageAPI.fetch()
            updatedAt = Date()
            error = nil
            interval = Self.normalInterval
        } catch FetchError.badResponse(429) {
            interval = min(interval * 2, Self.maxInterval)
            nextAllowed = Date() + interval
            error = Self.pausedMessage(until: nextAllowed)
        } catch let e as FetchError {
            error = e.message  // keep last good numbers on screen
        } catch {
            self.error = "Couldn't reach Claude. Will retry in 5 minutes."
        }
    }

    var canRefreshNow: Bool {
        !loading && Date() >= nextAllowed && Date().timeIntervalSince(lastAttempt) >= Self.manualMinGap
    }

    private static func pausedMessage(until: Date) -> String {
        "Claude is rate limiting usage checks. Paused until \(until.formatted(date: .omitted, time: .shortened))."
    }

    private func save() {
        let s = Saved(limits: limits, updatedAt: updatedAt, lastAttempt: lastAttempt,
                      nextAllowed: nextAllowed, interval: interval)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "saved") }
    }

    /// The limit that matters most: highest usage among windows still open.
    var headline: Limit? { limits.max { $0.used < $1.used } }
}

// MARK: - Views

struct PaceBar: View {
    let fill: Double  // 0...1
    let pace: Double  // 0...1, where an even pace would put the fill
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: max(geo.size.width * min(max(fill, 0), 1), 6))
                Rectangle()
                    .fill(.primary.opacity(0.55))
                    .frame(width: 2, height: geo.size.height + 6)
                    .offset(x: geo.size.width * pace - 1)
                    .help("Even pace")
            }
        }
        .frame(height: 8)
    }
}

struct LimitRow: View {
    let limit: Limit
    let now: Date
    @AppStorage("showRemaining") private var showRemaining = true

    private var runsOut: Date? { limit.runsOut(now) }
    private var left: Double { max(100 - limit.used, 0) }
    private var tint: Color {
        if limit.used >= 90 { return .red }
        return runsOut != nil ? .orange : .quotaMint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.name).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(showRemaining ? "\(Int(left.rounded()))% left" : "\(Int(limit.used.rounded()))% used")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            // Remaining mode drains like a fuel gauge; the tick is where an even pace leaves you.
            PaceBar(fill: showRemaining ? left / 100 : limit.used / 100,
                    pace: showRemaining ? 1 - limit.elapsed(now) : limit.elapsed(now),
                    tint: tint)
            Group {
                if let runsOut {
                    Text("At this pace you run out \(runsOut.formatted(.relative(presentation: .named))), \(runsOut.formatted(.dateTime.weekday().hour().minute()))")
                        .foregroundStyle(tint)
                } else if showRemaining {
                    Text("On pace to have \(Int((100 - limit.projected(now)).rounded()))% left at reset")
                } else {
                    Text("On pace for \(Int(limit.projected(now).rounded()))% by reset")
                }
            }
            .font(.system(size: 11))
            Text("Resets \(limit.resetsAt.formatted(.dateTime.weekday().hour().minute())) · \(limit.resetsAt.formatted(.relative(presentation: .named)))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct Panel: View {
    @ObservedObject var store: UsageStore
    @AppStorage("showRemaining") private var showRemaining = true

    // Lives in the store, not @State: @State is a macro in recent SDKs, and macro
    // plugins fail to load in Homebrew's build environment.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) })
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 14) {
                Text("Claude plan usage").font(.system(size: 13, weight: .semibold))

                if store.limits.isEmpty && store.error == nil {
                    if store.updatedAt == nil {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Text("No plan limits reported for this account.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                ForEach(store.limits) { LimitRow(limit: $0, now: ctx.date) }

                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack {
                    if let u = store.updatedAt {
                        Text("Updated \(u.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.refresh(manual: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.canRefreshNow)
                    .help(store.canRefreshNow ? "Refresh" : "Checked recently")
                    Menu {
                        Toggle("Show remaining", isOn: $showRemaining)
                        Toggle("Open at login", isOn: launchAtLogin)
                        Divider()
                        Button("Quit QuotaBar") { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(16)
            .frame(width: 300)
            .onAppear { store.refreshLoginStatus() }
        }
    }
}

extension Color {
    /// Brand colour: "on pace". Warnings stay system orange and red.
    static let quotaMint = Color(red: 0.24, green: 0.86, blue: 0.59)  // #3DDC97
}

/// The QuotaBar mark as a live menu bar glyph: a track, a fill and an even-pace tick.
/// Template image, so macOS tints it for light, dark and highlighted menu bars.
enum MenuGlyph {
    static func image(fill: Double, tick: Double?) -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { rect in
            let th: CGFloat = 6, w = rect.width - 2, x0: CGFloat = 1
            let y = (rect.height - th) / 2
            NSColor.black.withAlphaComponent(0.32).setFill()
            NSBezierPath(roundedRect: NSRect(x: x0, y: y, width: w, height: th), xRadius: th / 2, yRadius: th / 2).fill()
            let f = min(max(fill, 0), 1)
            if f > 0 {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: x0, y: y, width: max(w * f, th), height: th),
                             xRadius: th / 2, yRadius: th / 2).fill()
            }
            if let tick {
                let x = x0 + w * min(max(tick, 0), 1)
                NSGraphicsContext.current?.compositingOperation = .clear  // gap either side of the tick
                NSBezierPath(roundedRect: NSRect(x: x - 2.25, y: 0, width: 4.5, height: rect.height),
                             xRadius: 2.25, yRadius: 2.25).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: x - 1, y: 1, width: 2, height: rect.height - 2),
                             xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

struct MenuLabel: View {
    @ObservedObject var store: UsageStore
    @AppStorage("showRemaining") private var showRemaining = true

    var body: some View {
        if let h = store.headline {
            let elapsed = h.elapsed(Date())
            Image(nsImage: showRemaining
                  ? MenuGlyph.image(fill: (100 - h.used) / 100, tick: 1 - elapsed)
                  : MenuGlyph.image(fill: h.used / 100, tick: elapsed))
            Text(showRemaining ? "\(Int(max(100 - h.used, 0).rounded()))% left" : "\(Int(h.used.rounded()))%")
        } else {
            Image(nsImage: MenuGlyph.image(fill: 0, tick: nil))
        }
    }
}

@main
struct QuotaBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            MenuLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
