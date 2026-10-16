import Foundation

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

/// "3 days before" / "3일 전"; 0 means day-of only.
func daysBefore(_ n: Int) -> String {
    switch n {
    case 0: return L("Day of only")
    case 1: return L("1 day before")
    default: return L("%d days before", n)
    }
}

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
        case .weekly: return L("Weekly")
        case .monthly: return L("Monthly")
        case .quarterly: return L("Every 3 months")
        case .yearly: return L("Yearly")
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
        case .active: return L("Active")
        case .trial: return L("Free trial")
        case .cancelled: return L("Cancelled")
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

    /// One charge converted to the base currency. usdRate = how many KRW one USD buys.
    func charge(in base: Currency, usdRate: Double) -> Double {
        if currency == base { return price }
        guard usdRate > 0 else { return 0 }
        return currency == .usd ? price * usdRate : price / usdRate
    }

    func monthly(in base: Currency, usdRate: Double) -> Double {
        guard status == .active else { return 0 }
        return charge(in: base, usdRate: usdRate) * cycle.perMonth
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

    /// Totals: whole won, or dollars with cents only when needed.
    static func total(_ value: Double, _ base: Currency) -> String {
        money(base == .krw ? value.rounded() : (value * 100).rounded() / 100, base)
    }

    static func date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        f.setLocalizedDateFormatFromTemplate(sameYear ? "MMMdE" : "yMMMd")
        return f.string(from: date)
    }

    static func daysUntil(_ date: Date, from today: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: date)).day ?? 0
    }

    static func dday(_ date: Date) -> String {
        let d = daysUntil(date)
        if d == 0 { return L("Today") }
        if d > 0 { return L("in %dd", d) }
        return L("%dd ago", -d)
    }
}
