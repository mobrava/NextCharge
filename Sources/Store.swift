import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

enum Scope: Hashable {
    case all, ungrouped, group(String)
}

@MainActor
final class Store: ObservableObject {
    @Published var items: [Subscription] = [] { didSet { save(); reschedule() } }

    @AppStorage("usdRate") var usdRate: Double = 1400 { willSet { objectWillChange.send() } }
    @AppStorage("baseCurrency") var baseCurrency: Currency = Locale.current.region?.identifier == "KR" ? .krw : .usd {
        willSet { objectWillChange.send() }
    }
    @AppStorage("leadDays") var leadDays: Int = 3 { willSet { objectWillChange.send() } }
    @AppStorage("notifyHour") var notifyHour: Int = 10 { willSet { objectWillChange.send() } }

    private let fileURL: URL
    private var loading = false
    private var lastData: Data?
    private var lastModified: Date?
    private var watcher: Timer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextCharge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("subscriptions.json")
        load()
        watchFile()
    }

    /// Picks up edits made to the JSON file outside the app (by hand or by an agent).
    private func watchFile() {
        watcher = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    private func reloadIfChanged() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let mtime = attrs?[.modificationDate] as? Date
        guard mtime != lastModified else { return }
        lastModified = mtime
        guard let data = try? Data(contentsOf: fileURL), data != lastData else { return }
        load()
    }

    // MARK: Groups

    /// Empty folders created from the sidebar before anything is moved into them.
    @Published var extraGroups: [String] = UserDefaults.standard.stringArray(forKey: "extraGroups") ?? [] {
        didSet { UserDefaults.standard.set(extraGroups, forKey: "extraGroups") }
    }

    var groups: [String] {
        let used = items.compactMap { $0.group?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Array(Set(used + extraGroups)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func items(in scope: Scope) -> [Subscription] {
        switch scope {
        case .all: return items
        case .ungrouped: return items.filter { ($0.group ?? "").isEmpty }
        case .group(let g): return items.filter { $0.group == g }
        }
    }

    func addGroup(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !groups.contains(n) else { return }
        extraGroups.append(n)
    }

    func renameGroup(_ old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old else { return }
        items = items.map { var s = $0; if s.group == old { s.group = n }; return s }
        extraGroups = extraGroups.map { $0 == old ? n : $0 }
    }

    /// Removes the folder; its subscriptions become ungrouped.
    func removeGroup(_ name: String) {
        items = items.map { var s = $0; if s.group == name { s.group = nil }; return s }
        extraGroups.removeAll { $0 == name }
    }

    func move(_ ids: [UUID], to group: String?) {
        items = items.map { var s = $0; if ids.contains(s.id) { s.group = group }; return s }
    }

    // MARK: Derived

    func sorted(_ list: [Subscription]) -> [Subscription] {
        list.sorted { a, b in
            if (a.status == .cancelled) != (b.status == .cancelled) { return b.status == .cancelled }
            return a.keyDate() < b.keyDate()
        }
    }

    var sorted: [Subscription] { sorted(items) }

    func monthlyTotal(_ list: [Subscription]) -> Double { list.reduce(0) { $0 + $1.monthly(in: baseCurrency, usdRate: usdRate) } }
    var monthlyTotal: Double { monthlyTotal(items) }

    /// Charges that will actually hit the card in the next 30 days (trials converting included).
    func next30Days(_ list: [Subscription]) -> Double {
        let limit = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        var total = 0.0
        for s in list {
            switch s.status {
            case .active:
                for d in s.upcomingCharges(6) where d <= limit { total += s.charge(in: baseCurrency, usdRate: usdRate) }
            case .trial:
                if let end = s.endDate, end <= limit, s.price > 0 { total += s.charge(in: baseCurrency, usdRate: usdRate) }
            case .cancelled:
                break
            }
        }
        return total
    }

    func nextUp(_ list: [Subscription]) -> Subscription? {
        list.filter { $0.status != .cancelled }.min { $0.keyDate() < $1.keyDate() }
    }

    // MARK: Mutations

    func upsert(_ s: Subscription) {
        if let i = items.firstIndex(where: { $0.id == s.id }) { items[i] = s } else { items.append(s) }
    }

    func delete(_ id: UUID) { items.removeAll { $0.id == id } }

    // MARK: Persistence

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Keep the current list if an external edit left the file half-written or invalid.
        guard let decoded = try? decoder.decode([Subscription].self, from: data) else { return }
        lastData = data
        lastModified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        items = decoded
    }

    private func save() {
        guard !loading else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
            lastData = data
            lastModified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        }
    }

    var dataFolder: URL { fileURL.deletingLastPathComponent() }

    // MARK: Reminders

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.reschedule() }
        }
    }

    @Published var notificationStatus: String = L("Checking")

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let text: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: text = settings.alertSetting == .enabled ? L("Allowed") : L("Allowed (banners off)")
            case .denied: text = L("Denied")
            case .notDetermined: text = L("Not asked yet")
            default: text = L("Unknown")
            }
            Task { @MainActor in self.notificationStatus = text }
        }
    }

    /// Asks for permission if needed, then fires a notification in 2 seconds.
    func sendTestNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.refreshNotificationStatus()
                if granted {
                    self.reschedule()
                } else {
                    // Already denied: only System Settings can turn it back on.
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = L("NextCharge test")
            content.body = L("Payment reminders will look like this.")
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-\(UUID())", content: content, trigger: trigger))
        }
    }

    func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let cal = Calendar.current
        let now = Date()
        var requests: [UNNotificationRequest] = []

        func add(id: String, title: String, body: String, on day: Date) {
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = notifyHour
            guard let fire = cal.date(from: comps), fire > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        for s in items {
            let price = Fmt.money(s.price, s.currency)
            let leadDays = s.remindDays ?? self.leadDays
            if leadDays < 0 { continue }
            switch s.status {
            case .active:
                // Three cycles ahead so reminders survive weeks without opening the app.
                for (n, date) in s.upcomingCharges(3).enumerated() {
                    if leadDays > 0 {
                        let lead = cal.date(byAdding: .day, value: -leadDays, to: date)!
                        add(id: "\(s.id)-c\(n)", title: L("%1$@ renews %2$@", s.name, Fmt.date(date)),
                            body: price, on: lead)
                    }
                    add(id: "\(s.id)-d\(n)", title: L("%@ renews today", s.name), body: price, on: date)
                }
            case .trial:
                guard let end = s.endDate else { continue }
                let tail = s.price > 0 ? L("Then %@", price) : L("Reverts to free")
                if leadDays > 0 {
                    let lead = cal.date(byAdding: .day, value: -leadDays, to: end)!
                    add(id: "\(s.id)-t0", title: L("%1$@ trial ends %2$@", s.name, Fmt.date(end)), body: tail, on: lead)
                }
                add(id: "\(s.id)-t1", title: L("%@ trial ends today", s.name), body: tail, on: end)
            case .cancelled:
                continue
            }
        }

        // macOS keeps at most 64 pending requests per app; keep the soonest.
        let soonest = requests.sorted {
            ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture <
            ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
        }.prefix(64)
        for r in soonest { center.add(r) }
    }

    // MARK: Login item

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}
