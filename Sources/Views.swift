import SwiftUI

// MARK: - Main window

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Subscription?
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Header()
            Divider()
            if store.items.isEmpty {
                ContentUnavailableView {
                    Label("구독 없음", systemImage: "creditcard")
                } actions: {
                    Button("구독 추가") { editing = Subscription() }
                        .keyboardShortcut("n")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    let active = store.sorted.filter { $0.status != .cancelled }
                    let cancelled = store.sorted.filter { $0.status == .cancelled }
                    Section {
                        ForEach(active) { row($0) }
                    }
                    if !cancelled.isEmpty {
                        Section("해지함") {
                            ForEach(cancelled) { row($0) }
                        }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand { if let id = selection { store.delete(id) } }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = Subscription() } label: { Label("추가", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $editing) { sub in
            EditView(draft: sub, isNew: !store.items.contains { $0.id == sub.id })
        }
    }

    @ViewBuilder
    private func row(_ s: Subscription) -> some View {
        SubscriptionRow(sub: s)
            .tag(s.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editing = s }
            .contextMenu {
                Button("수정") { editing = s }
                if let url = URL(string: s.manageURL), !s.manageURL.isEmpty {
                    Button("관리 페이지 열기") { NSWorkspace.shared.open(url) }
                }
                if s.status != .cancelled {
                    Button("해지함으로 표시") {
                        var c = s
                        c.status = .cancelled
                        if c.endDate == nil { c.endDate = s.nextCharge() }
                        store.upsert(c)
                    }
                }
                Divider()
                Button("삭제", role: .destructive) { store.delete(s.id) }
            }
    }
}

struct Header: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            figure("월 고정비", Fmt.krw(store.monthlyTotal), big: true)
            figure("연 환산", Fmt.krw(store.monthlyTotal * 12))
            figure("30일 안에 결제", Fmt.krw(store.next30Days))
            Spacer()
            if let n = store.nextUp {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.dday(n.keyDate()))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ddayColor(n.keyDate()))
                    Text(n.name).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func figure(_ label: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: big ? 30 : 17, weight: big ? .bold : .medium, design: .rounded))
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

func priceText(_ s: Subscription) -> String {
    if s.price > 0 { return Fmt.money(s.price, s.currency) }
    return s.status == .trial ? "무료" : "금액 미입력"
}

func ddayColor(_ date: Date) -> Color {
    let d = Fmt.daysUntil(date)
    if d <= 3 { return .red }
    if d <= 7 { return .orange }
    return .primary
}

struct SubscriptionRow: View {
    @EnvironmentObject var store: Store
    let sub: Subscription

    var body: some View {
        HStack(spacing: 12) {
            Monogram(name: sub.name, dimmed: sub.status == .cancelled)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name.isEmpty ? "이름 없음" : sub.name)
                    .font(.body.weight(.medium))
                    .strikethrough(sub.status == .cancelled, color: .secondary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(priceText(sub))
                    .monospacedDigit()
                    .foregroundStyle(sub.status == .cancelled || sub.price == 0 ? .secondary : .primary)
                if sub.currency == .usd && sub.price > 0 {
                    Text("≈ " + Fmt.krw(sub.chargeKRW(usdRate: store.usdRate)))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Text(Fmt.dday(sub.keyDate()))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(sub.status == .cancelled ? .secondary : ddayColor(sub.keyDate()))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts: [String] = []
        switch sub.status {
        case .active: parts.append("\(sub.cycle.label) · \(Fmt.date(sub.nextCharge())) 결제")
        case .trial: parts.append("체험 \(sub.endDate.map(Fmt.date) ?? "") 종료")
        case .cancelled: parts.append("\(sub.endDate.map(Fmt.date) ?? "") 까지 이용")
        }
        if !sub.paymentMethod.isEmpty { parts.append(sub.paymentMethod) }
        return parts.joined(separator: " · ")
    }
}

struct Monogram: View {
    let name: String
    var dimmed = false

    var body: some View {
        let letter = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        Text(letter)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(color.opacity(dimmed ? 0.35 : 1)))
    }

    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .brown, .cyan, .mint]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

// MARK: - Edit sheet

struct EditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var draft: Subscription
    let isNew: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("이름", text: $draft.name)
                    HStack {
                        TextField("금액", value: $draft.price, format: .number)
                        Picker("", selection: $draft.currency) {
                            ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    Picker("주기", selection: $draft.cycle) {
                        ForEach(Cycle.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("결제일", selection: $draft.billingAnchor, displayedComponents: .date)
                }
                Section {
                    Picker("상태", selection: $draft.status) {
                        ForEach(Status.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if draft.status != .active {
                        DatePicker(draft.status == .trial ? "체험 종료일" : "이용 종료일",
                                   selection: Binding(get: { draft.endDate ?? draft.nextCharge() },
                                                      set: { draft.endDate = $0 }),
                                   displayedComponents: .date)
                    }
                }
                Section {
                    TextField("결제 수단", text: $draft.paymentMethod, prompt: Text("카드 끝자리 1234"))
                    TextField("관리 페이지", text: $draft.manageURL, prompt: Text("https://"))
                    TextField("메모", text: $draft.notes, axis: .vertical).lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("삭제", role: .destructive) { store.delete(draft.id); dismiss() }
                }
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "추가" : "저장") {
                    if draft.status == .active { draft.endDate = nil }
                    store.upsert(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 440, height: 520)
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.krw(store.monthlyTotal))
                    .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                Text("/ 월").foregroundStyle(.secondary)
            }
            Divider()
            let upcoming = store.sorted.filter { $0.status != .cancelled }.prefix(6)
            if upcoming.isEmpty {
                Text("구독 없음").foregroundStyle(.secondary)
            }
            ForEach(Array(upcoming)) { s in
                HStack {
                    Text(s.name).lineLimit(1)
                    Spacer()
                    Text(priceText(s)).foregroundStyle(.secondary).monospacedDigit()
                    Text(Fmt.dday(s.keyDate()))
                        .monospacedDigit()
                        .foregroundStyle(ddayColor(s.keyDate()))
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.callout)
            }
            Divider()
            HStack {
                Button("열기") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            TextField("1 USD =", value: $store.usdRate, format: .number)
            Stepper("결제 \(store.leadDays)일 전에 알림", value: $store.leadDays, in: 0...14)
                .onChange(of: store.leadDays) { store.reschedule() }
            Stepper("알림 시각 \(store.notifyHour)시", value: $store.notifyHour, in: 0...23)
                .onChange(of: store.notifyHour) { store.reschedule() }
            Toggle("로그인 시 실행", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
            LabeledContent("데이터") {
                Button("Finder에서 보기") { NSWorkspace.shared.open(store.dataFolder) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
