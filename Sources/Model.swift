import Foundation

enum Currency: String, Codable, CaseIterable, Identifiable {
    case krw = "KRW"
    case usd = "USD"

    var id: String { rawValue }
    var symbol: String { self == .krw ? "₩" : "$" }
}

enum Cycle: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekly: return "매주"
        case .monthly: return "매월"
        case .quarterly: return "3개월"
        case .yearly: return "매년"
        }
    }

    /// Multiplier that turns one charge into a monthly equivalent.
    var perMonth: Double {
        switch self {
        case .weekly: return 52.0 / 12.0
        case .monthly: return 1
        case .quarterly: return 1.0 / 3.0
        case .yearly: return 1.0 / 12.0
        }
    }

    func advance(_ date: Date, by steps: Int = 1, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly: return calendar.date(byAdding: .day, value: 7 * steps, to: date)!
        case .monthly: return calendar.date(byAdding: .month, value: steps, to: date)!
        case .quarterly: return calendar.date(byAdding: .month, value: 3 * steps, to: date)!
        case .yearly: return calendar.date(byAdding: .year, value: steps, to: date)!
        }
    }
}

enum Status: String, Codable, CaseIterable, Identifiable {
    case active, trial, cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: return "사용 중"
        case .trial: return "무료 체험"
        case .cancelled: return "해지함"
        }
    }
}

struct Subscription: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    var price: Double = 0
    var currency: Currency = .krw
    var cycle: Cycle = .monthly
    /// Any past or future billing date. Upcoming dates are derived from it.
    var billingAnchor: Date = Calendar.current.startOfDay(for: Date())
    var status: Status = .active
    /// For trials: the day it converts to paid. For cancelled: the day access ends.
    var endDate: Date? = nil
    var paymentMethod: String = ""
    var manageURL: String = ""
    var notes: String = ""
    /// Optional override for where the logo comes from (e.g. "slack.com").
    var iconDomain: String? = nil
    /// Folder this subscription belongs to (e.g. "fconlab"). nil = no group.
    var group: String? = nil
    /// Days before the charge to remind. nil = app default, 0 = day-of only, -1 = off.
    var remindDays: Int? = nil

    /// Host used to look up the logo: the override if set, otherwise the manage URL's host.
    var logoHost: String? {
        if let d = iconDomain?.trimmingCharacters(in: .whitespaces), !d.isEmpty {
            return URL(string: d.contains("://") ? d : "https://" + d)?.host?.lowercased()
        }
        let raw = manageURL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw.contains("://") ? raw : "https://" + raw)?.host?.lowercased()
    }

    /// Next billing date. A future anchor is the next charge itself. An anchor of today or
    /// earlier counts as already paid, so the next charge is the first later recurrence that
    /// falls on today or after (a recurrence landing today shows as due today).
    func nextCharge(from today: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: today)
        let anchor = calendar.startOfDay(for: billingAnchor)
        if anchor > start { return anchor }
        var steps = 1
        while true {
            let candidate = cycle.advance(calendar.startOfDay(for: billingAnchor), by: steps, calendar: calendar)
            if candidate >= start { return candidate }
            steps += 1
        }
    }

    /// Next N charge dates, used for scheduling reminders.
    func upcomingCharges(_ count: Int, from today: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let first = nextCharge(from: today, calendar: calendar)
        return (0..<count).map { cycle.advance(first, by: $0, calendar: calendar) }
    }

    /// The date that matters most right now: trial end, access end, or next charge.
    func keyDate(from today: Date = Date()) -> Date {
        switch status {
        case .trial, .cancelled:
            return endDate ?? nextCharge(from: today)
        case .active:
            return nextCharge(from: today)
        }
    }

    func monthlyKRW(usdRate: Double) -> Double {
        guard status == .active else { return 0 }
        let krw = currency == .usd ? price * usdRate : price
        return krw * cycle.perMonth
    }

    func chargeKRW(usdRate: Double) -> Double {
        currency == .usd ? price * usdRate : price
    }
}

enum Fmt {
    static func money(_ value: Double, _ currency: Currency) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = currency == .krw ? 0 : 2
        f.minimumFractionDigits = currency == .krw ? 0 : (value.rounded() == value ? 0 : 2)
        return currency.symbol + (f.string(from: NSNumber(value: value)) ?? "\(value)")
    }

    static func krw(_ value: Double) -> String { money(value.rounded(), .krw) }

    static func date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "M월 d일 (E)" : "yyyy년 M월 d일"
        return f.string(from: date)
    }

    static func daysUntil(_ date: Date, from today: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: date)).day ?? 0
    }

    static func dday(_ date: Date) -> String {
        let d = daysUntil(date)
        if d == 0 { return "오늘" }
        if d > 0 { return "D-\(d)" }
        return "D+\(-d)"
    }
}
