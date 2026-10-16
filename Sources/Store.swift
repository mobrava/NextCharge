import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published var items: [Subscription] = [] { didSet { save(); reschedule() } }

    @AppStorage("usdRate") var usdRate: Double = 1400 { willSet { objectWillChange.send() } }
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

    // MARK: Derived

    var sorted: [Subscription] {
        items.sorted { a, b in
            if (a.status == .cancelled) != (b.status == .cancelled) { return b.status == .cancelled }
            return a.keyDate() < b.keyDate()
        }
    }

    var monthlyTotal: Double { items.reduce(0) { $0 + $1.monthlyKRW(usdRate: usdRate) } }

    /// Charges that will actually hit the card in the next 30 days (trials converting included).
    var next30Days: Double {
        let limit = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        var total = 0.0
        for s in items {
            switch s.status {
            case .active:
                for d in s.upcomingCharges(6) where d <= limit { total += s.chargeKRW(usdRate: usdRate) }
            case .trial:
                if let end = s.endDate, end <= limit, s.price > 0 { total += s.chargeKRW(usdRate: usdRate) }
            case .cancelled:
                break
            }
        }
        return total
    }

    var nextUp: Subscription? {
        items.filter { $0.status != .cancelled }.min { $0.keyDate() < $1.keyDate() }
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
            switch s.status {
            case .active:
                // Three cycles ahead so reminders survive weeks without opening the app.
                for (n, date) in s.upcomingCharges(3).enumerated() {
                    let lead = cal.date(byAdding: .day, value: -leadDays, to: date)!
                    add(id: "\(s.id)-c\(n)", title: "\(s.name) \(leadDays)일 뒤 결제",
                        body: "\(Fmt.date(date)) \(price)", on: lead)
                    add(id: "\(s.id)-d\(n)", title: "오늘 \(s.name) 결제", body: price, on: date)
                }
            case .trial:
                guard let end = s.endDate else { continue }
                let lead = cal.date(byAdding: .day, value: -leadDays, to: end)!
                let tail = s.price > 0 ? "이후 \(price) 결제" : "끝나면 무료로 돌아감"
                add(id: "\(s.id)-t0", title: "\(s.name) 체험 \(leadDays)일 남음", body: "\(Fmt.date(end)) 종료, \(tail)", on: lead)
                add(id: "\(s.id)-t1", title: "오늘 \(s.name) 체험 종료", body: tail, on: end)
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
