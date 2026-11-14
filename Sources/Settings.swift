// Settings: every user-tunable value lives here, stored in UserDefaults (domain com.longroadsoftware.claudeusagemeter).
import Foundation
import ServiceManagement

enum ShowValue: String, CaseIterable, Identifiable { case remaining, used; var id: String { rawValue } }
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case ringAndText, ringAndPercent, textOnly, ringOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ringAndText: return "Ring + \"Claude 3% remaining\""
        case .ringAndPercent: return "Ring + \"3%\""
        case .textOnly: return "Text only"
        case .ringOnly: return "Ring only"
        }
    }
}
enum LimitChoice: String, CaseIterable, Identifiable {
    case tightestAccount, tightestAny, week, session
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tightestAccount: return "Tightest account-wide limit"
        case .tightestAny: return "Tightest limit, including model-only caps"
        case .week: return "Weekly limit"
        case .session: return "5-hour session limit"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var source: Source { didSet { d.set(source.rawValue, forKey: "source") } }
    @Published var command: String { didSet { d.set(command, forKey: "command") } }
    @Published var refreshMinutes: Double { didSet { d.set(refreshMinutes, forKey: "refreshMinutes") } }
    @Published var requestTimeout: Double { didSet { d.set(requestTimeout, forKey: "requestTimeout") } }
    @Published var staleMinutes: Double { didSet { d.set(staleMinutes, forKey: "staleMinutes") } }
    @Published var show: ShowValue { didSet { d.set(show.rawValue, forKey: "show") } }
    @Published var limit: LimitChoice { didSet { d.set(limit.rawValue, forKey: "limit") } }
    @Published var menuBarStyle: MenuBarStyle { didSet { d.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    @Published var label: String { didSet { d.set(label, forKey: "label") } }
    @Published var warnBelow: Double { didSet { d.set(warnBelow, forKey: "warnBelow") } }      // % remaining -> orange
    @Published var criticalBelow: Double { didSet { d.set(criticalBelow, forKey: "criticalBelow") } } // % remaining -> red
    @Published var colorText: Bool { didSet { d.set(colorText, forKey: "colorText") } }
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock") } }
    @Published var notifyBelow: Double { didSet { d.set(notifyBelow, forKey: "notifyBelow") } }  // 0 = off

    private init() {
        source = Source(rawValue: d.string(forKey: "source") ?? "") ?? .automatic
        command = d.string(forKey: "command") ?? ""
        refreshMinutes = d.object(forKey: "refreshMinutes") as? Double ?? 5
        requestTimeout = d.object(forKey: "requestTimeout") as? Double ?? 15
        staleMinutes = d.object(forKey: "staleMinutes") as? Double ?? 20
        show = ShowValue(rawValue: d.string(forKey: "show") ?? (d.bool(forKey: "showUsed") ? "used" : "")) ?? .remaining
        limit = LimitChoice(rawValue: d.string(forKey: "limit") ?? "") ?? .tightestAccount
        menuBarStyle = MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .ringAndText
        label = d.string(forKey: "label") ?? "Claude"
        warnBelow = d.object(forKey: "warnBelow") as? Double ?? 30
        criticalBelow = d.object(forKey: "criticalBelow") as? Double ?? 10
        colorText = d.object(forKey: "colorText") as? Bool ?? false
        showInDock = d.object(forKey: "showInDock") as? Bool ?? false
        notifyBelow = d.object(forKey: "notifyBelow") as? Double ?? 0
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { NSLog("Launch at login: \(error)") }
        }
    }

    func pick(_ r: Reading) -> Limit? {
        let account = r.limits.filter { !$0.modelScoped }
        switch limit {
        case .tightestAccount: return (account.isEmpty ? r.limits : account).max { $0.used < $1.used }
        case .tightestAny: return r.limits.max { $0.used < $1.used }
        case .week: return account.first { $0.label.lowercased().hasPrefix("week") } ?? pickFallback(r)
        case .session: return account.first { $0.label.lowercased().hasPrefix("session") } ?? pickFallback(r)
        }
    }
    private func pickFallback(_ r: Reading) -> Limit? { r.limits.filter { !$0.modelScoped }.max { $0.used < $1.used } }

    func level(remaining: Double) -> Int { remaining < criticalBelow ? 2 : remaining < warnBelow ? 1 : 0 }
}
