import SwiftUI

// MARK: - Main window

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var scope: Scope? = .all
    @State private var editing: Subscription?
    @State private var selection: Set<UUID> = []
    @State private var groupPrompt: GroupPrompt?
    @State private var groupName = ""

    private var current: Scope { scope ?? .all }
    private var list: [Subscription] { store.items(in: current) }

    var body: some View {
        NavigationSplitView {
            Sidebar(scope: $scope, onNewGroup: { groupName = ""; groupPrompt = .new },
                    onRename: { g in groupName = g; groupPrompt = .rename(g) })
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 460)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = newSubscription() } label: { Label("추가", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $editing) { sub in
            EditView(draft: sub, isNew: !store.items.contains { $0.id == sub.id })
        }
        .alert(groupPrompt?.title ?? "", isPresented: Binding(get: { groupPrompt != nil }, set: { if !$0 { groupPrompt = nil } })) {
            TextField("이름", text: $groupName)
            Button("취소", role: .cancel) { groupPrompt = nil }
            Button("확인") {
                switch groupPrompt {
                case .new:
                    store.addGroup(groupName)
                    scope = .group(groupName.trimmingCharacters(in: .whitespaces))
                case .rename(let old):
                    store.renameGroup(old, to: groupName)
                    if scope == .group(old) { scope = .group(groupName.trimmingCharacters(in: .whitespaces)) }
                case nil: break
                }
                groupPrompt = nil
            }
        }
    }

    private func newSubscription() -> Subscription {
        var s = Subscription()
        if case .group(let g) = current { s.group = g }
        return s
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            Header(list: list)
            Divider()
            if list.isEmpty {
                ContentUnavailableView {
                    Label("구독 없음", systemImage: "creditcard")
                } actions: {
                    Button("구독 추가") { editing = newSubscription() }
                }
                .frame(maxHeight: .infinity)
            } else {
                let sorted = store.sorted(list)
                let live = sorted.filter { $0.status != .cancelled }
                let cancelled = sorted.filter { $0.status == .cancelled }
                List(selection: $selection) {
                    Section { ForEach(live) { row($0) } }
                    if !cancelled.isEmpty {
                        Section("해지함") { ForEach(cancelled) { row($0) } }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand { selection.forEach(store.delete) ; selection = [] }
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch current {
        case .all: return "전체"
        case .ungrouped: return "그룹 없음"
        case .group(let g): return g
        }
    }

    @ViewBuilder
    private func row(_ s: Subscription) -> some View {
        SubscriptionRow(sub: s, showGroup: current == .all)
            .tag(s.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editing = s }
            .draggable(s.id.uuidString)
            .contextMenu {
                Button("수정") { editing = s }
                if let url = URL(string: s.manageURL), !s.manageURL.isEmpty {
                    Button("관리 페이지 열기") { NSWorkspace.shared.open(url) }
                }
                Menu("그룹으로 이동") {
                    let ids = selection.contains(s.id) ? Array(selection) : [s.id]
                    ForEach(store.groups, id: \.self) { g in
                        Button(g) { store.move(ids, to: g) }.disabled(s.group == g && ids.count == 1)
                    }
                    Divider()
                    Button("그룹 없음") { store.move(ids, to: nil) }
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

enum GroupPrompt: Equatable {
    case new, rename(String)
    var title: String {
        switch self {
        case .new: return "새 그룹"
        case .rename: return "그룹 이름 바꾸기"
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @Binding var scope: Scope?
    let onNewGroup: () -> Void
    let onRename: (String) -> Void

    var body: some View {
        List(selection: $scope) {
            item("전체", icon: "tray.full", scope: .all, group: nil)
            Section("그룹") {
                ForEach(store.groups, id: \.self) { g in
                    item(g, icon: "folder", scope: .group(g), group: g)
                        .contextMenu {
                            Button("이름 바꾸기") { onRename(g) }
                            Button("그룹 삭제 (구독은 그룹 없음으로)", role: .destructive) {
                                store.removeGroup(g)
                                if scope == .group(g) { scope = .all }
                            }
                        }
                }
                if store.items.contains(where: { ($0.group ?? "").isEmpty }) {
                    item("그룹 없음", icon: "tray", scope: .ungrouped, group: "")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: onNewGroup) { Label("새 그룹", systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .padding(10)
        }
    }

    /// group: nil = not a drop target, "" = drop to ungroup, otherwise folder name.
    private func item(_ name: String, icon: String, scope: Scope, group: String?) -> some View {
        HStack {
            Label(name, systemImage: icon)
            Spacer()
            let total = store.monthlyTotal(store.items(in: scope))
            if total > 0 {
                Text(Fmt.krw(total)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .tag(scope)
        .dropDestination(for: String.self) { ids, _ in
            guard let group else { return false }
            let uuids = ids.compactMap(UUID.init(uuidString:))
            store.move(uuids, to: group.isEmpty ? nil : group)
            return !uuids.isEmpty
        }
    }
}

struct Header: View {
    @EnvironmentObject var store: Store
    let list: [Subscription]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            let monthly = store.monthlyTotal(list)
            figure("월 고정비", Fmt.krw(monthly), big: true)
            figure("연 환산", Fmt.krw(monthly * 12))
            figure("30일 안에 결제", Fmt.krw(store.next30Days(list)))
            Spacer()
            if let n = store.nextUp(list) {
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
    var showGroup = false

    var body: some View {
        HStack(spacing: 12) {
            SubscriptionIcon(sub: sub)
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
        if showGroup, let g = sub.group, !g.isEmpty { parts.append(g) }
        return parts.joined(separator: " · ")
    }
}

struct Monogram: View {
    let name: String
    var dimmed = false
    var size: CGFloat = 30

    var body: some View {
        let letter = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        Text(letter)
            .font(.system(size: size * 0.47, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
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

    private var manageHost: String? {
        var s = draft
        s.iconDomain = nil
        return s.logoHost
    }

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
                    HStack {
                        TextField("그룹", text: Binding(get: { draft.group ?? "" },
                                                       set: { draft.group = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }),
                                  prompt: Text("없음"))
                        if !store.groups.isEmpty {
                            Menu {
                                ForEach(store.groups, id: \.self) { g in Button(g) { draft.group = g } }
                                Divider()
                                Button("그룹 없음") { draft.group = nil }
                            } label: { Image(systemName: "folder") }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                    Picker("알림", selection: $draft.remindDays) {
                        Text("기본 (\(store.leadDays)일 전)").tag(Int?.none)
                        Text("당일만").tag(Int?.some(0))
                        ForEach([1, 3, 7, 14], id: \.self) { d in Text("\(d)일 전").tag(Int?.some(d)) }
                        Text("끔").tag(Int?.some(-1))
                    }
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
                    HStack {
                        TextField("로고 도메인", text: Binding(get: { draft.iconDomain ?? "" },
                                                          set: { draft.iconDomain = $0.isEmpty ? nil : $0 }),
                                  prompt: Text(manageHost ?? "slack.com"))
                        SubscriptionIcon(sub: draft, size: 22)
                    }
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
        .frame(width: 440, height: 600)
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
                    SubscriptionIcon(sub: s, size: 18)
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
            LabeledContent("알림 권한") {
                HStack {
                    Text(store.notificationStatus).foregroundStyle(.secondary)
                    Button("테스트 알림") { store.sendTestNotification() }
                }
            }
            Toggle("로그인 시 실행", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
            LabeledContent("데이터") {
                Button("Finder에서 보기") { NSWorkspace.shared.open(store.dataFolder) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear { store.refreshNotificationStatus() }
        .fixedSize(horizontal: false, vertical: true)
    }
}
