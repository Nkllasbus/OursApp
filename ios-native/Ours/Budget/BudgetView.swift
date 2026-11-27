import SwiftUI
import Charts

/// Budget: Übersicht · Verträge · Budgets · Analyse
struct BudgetView: View {
    @Environment(Session.self) private var session
    @State private var store = BudgetStore()
    enum Tab: String, CaseIterable { case home = "Übersicht", contracts = "Verträge", plan = "Budgets", stats = "Analyse" }
    @State private var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "budget.tab") ?? "") ?? .home
    @State private var openTx: Transaction?
    @State private var addExpense = false
    @State private var connectBank = false
    @State private var pickCSV = false
    @State private var csvData: CSVRef?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Ansicht", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let m = store.message {
                    Text(m).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !store.loaded {
                    ProgressView().padding(.top, 40)
                } else {
                    switch tab {
                    case .home: BudgetHomeView(store: store, openTx: $openTx)
                    case .contracts: ContractsView(store: store)
                    case .plan: BudgetPlanView(store: store, openTx: $openTx)
                    case .stats: BudgetStatsView(store: store, openTx: $openTx)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await store.refresh() }
        .navigationTitle("Budget")
        .tint(BudgetCats.green)
        .task { if let uid = session.uid { await store.start(uid: uid) } }
        .onChange(of: tab) { UserDefaults.standard.set(tab.rawValue, forKey: "budget.tab") }
        .sensoryFeedback(.selection, trigger: tab)
        .sheet(item: $openTx) { t in TxSheet(store: store, tx: t) }
        .navigationDestination(for: TxFilter.self) { f in TxListView(store: store, filter: f) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if store.budgetSid != nil { Button("Ausgabe eintragen", systemImage: "square.and.pencil") { addExpense = true } }
                    Button("Konto verbinden", systemImage: "building.columns") { connectBank = true }
                    Button("CSV importieren", systemImage: "doc.text") { pickCSV = true }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $addExpense) { ExpenseSheet(store: store, tx: nil) }
        .sheet(isPresented: $connectBank) { BankConnectSheet(store: store) }
        .sheet(item: $csvData) { ref in CSVImportSheet(store: store, data: ref.data) }
        .fileImporter(isPresented: $pickCSV, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { res in
            guard case .success(let url) = res else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url), let c = BudgetStore.readCSV(d, fileName: url.lastPathComponent), !c.body.isEmpty {
                csvData = CSVRef(data: c)
            } else {
                store.message = "In der Datei wurden keine Umsätze gefunden."
            }
        }
    }
}

struct CSVRef: Identifiable { let id = UUID(); let data: BudgetStore.CSVData }

/// Welche Umsätze die Liste zeigt (alle oder ein Konto)
struct TxFilter: Hashable { let account: String? }

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Übersicht

struct BudgetHomeView: View {
    let store: BudgetStore
    @Binding var openTx: Transaction?

    var body: some View {
        let accs = store.accounts.values.sorted { ($0.balance ?? 0) > ($1.balance ?? 0) }
        let total = accs.reduce(0) { $0 + ($1.balance ?? 0) }
        VStack(spacing: 16) {
            ForEach(Array(store.eb.keys), id: \.self) { k in
                if let vu = store.eb[k]?["validUntil"] as? String, let d = ISO8601DateFormatter().date(from: vu), d.timeIntervalSinceNow / 86400 < 14 {
                    Label("Die Freigabe für \(store.eb[k]?["bank"] as? String ?? "deine Bank") \(d < Date() ? "ist abgelaufen" : "läuft bald ab"). Verbinde sie auf der Webseite neu.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.orange)
                }
            }
            Card {
                HStack {
                    Text("GESAMT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if store.syncing { ProgressView().controlSize(.small) }
                    else if store.lastSyncAt > 0 {
                        Text(ago(store.lastSyncAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(Money.text(total)).font(.system(size: 38, weight: .bold)).foregroundStyle(total < 0 ? BudgetCats.red : Color.primary)
                Text("\(store.rawTx.count) Umsätze · neuester vom \(store.newestText)").font(.caption).foregroundStyle(.secondary)
                ForEach(accs) { a in
                    NavigationLink(value: TxFilter(account: a.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: a.kind == "depot" ? "chart.line.uptrend.xyaxis" : "building.columns.fill")
                                .foregroundStyle(.white).frame(width: 38, height: 38)
                                .background(a.isPayPal ? Color(hex: 0x5A82BF) : BudgetCats.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(a.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(a.balance.map { Money.text($0) } ?? "–").font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle((a.balance ?? 0) < 0 ? BudgetCats.red : Color.primary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                if accs.isEmpty {
                    Text("Noch kein Konto. Verbinde deine Bank oder importiere eine CSV-Datei auf der Webseite.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                NavigationLink(value: TxFilter(account: nil)) {
                    Text("Alle Umsätze anzeigen").bold().frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
            }

            // gleich die neuesten Umsätze
            let recent = store.allTx.sorted { $0.date != $1.date ? $0.date > $1.date : abs($0.amount) > abs($1.amount) }.prefix(12)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Umsätze").font(.title3.bold())
                    Spacer()
                    NavigationLink("Alle", value: TxFilter(account: nil)).font(.subheadline.weight(.semibold))
                }
                TxDayList(store: store, list: Array(recent), openTx: $openTx)
            }

            MonthCard(store: store)
            InOutCard(store: store)
        }
    }

    private func ago(_ t: Double) -> String {
        let m = Int((DB.nowMs - t) / 60000)
        return m < 1 ? "gerade eben" : m < 60 ? "vor \(m) Min." : m < 1440 ? "vor \(m / 60) Std." : "vor \(m / 1440) Tagen"
    }
}

/// Umsätze nach Tag gruppiert
struct TxDayList: View {
    let store: BudgetStore
    let list: [Transaction]
    @Binding var openTx: Transaction?

    var body: some View {
        let days = Dictionary(grouping: list, by: \.date).sorted { $0.key > $1.key }
        VStack(alignment: .leading, spacing: 6) {
            if list.isEmpty { Text("Noch keine Umsätze.").foregroundStyle(.secondary) }
            ForEach(days, id: \.key) { day, items in
                Text(dayLabel(day)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6).padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(items) { t in
                        TxRow(store: store, tx: t).onTapGesture { openTx = t }
                        if t.id != items.last?.id { Divider().padding(.leading, 62) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

func dayLabel(_ d: String) -> String {
    let cal = Calendar.current, x = Gym.date(d)
    if cal.isDateInToday(x) { return "Heute" }
    if cal.isDateInYesterday(x) { return "Gestern" }
    return x.formatted(.dateTime.weekday(.wide).day().month(.wide))
}

struct TxRow: View {
    let store: BudgetStore
    let tx: Transaction
    var showDate = false

    var body: some View {
        let c = store.cat(tx), name = store.label(tx)
        HStack(spacing: 12) {
            Image(systemName: store.symbol(c))
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(store.tint(c), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name).font(.body.weight(.medium)).lineLimit(1)
                    if tx.pending { Text("vorgemerkt").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(Color(.tertiarySystemFill), in: Capsule()) }
                }
                Text(c + (showDate ? " · " + Gym.date(tx.date).formatted(.dateTime.day().month()) : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.signed(tx.amount)).font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(tx.amount > 0 ? BudgetCats.green : Color.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .opacity(tx.ex ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

struct MonthCard: View {
    let store: BudgetStore

    var body: some View {
        let now = Date(), cal = Calendar.current
        let t = store.totals(year: cal.component(.year, from: now), month: cal.component(.month, from: now))
        let cats = t.byCat.sorted { ($0.key == "Sonstiges" ? 1 : 0, -$0.value) < ($1.key == "Sonstiges" ? 1 : 0, -$1.value) }
        if !cats.isEmpty {
            Card {
                HStack {
                    Text(BudgetCats.months[cal.component(.month, from: now) - 1]).font(.title3.bold())
                    Spacer()
                    Text("+\(Money.text(t.inc)) · −\(Money.text(t.out))").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Chart(cats, id: \.key) { c in
                        SectorMark(angle: .value("Betrag", c.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(store.tint(c.key))
                    }
                    .frame(width: 130, height: 130)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("Ausgaben").font(.caption2).foregroundStyle(.secondary)
                            Text(Money.text(t.out)).font(.footnote.bold())
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cats.prefix(6), id: \.key) { c in
                            HStack(spacing: 6) {
                                Circle().fill(store.tint(c.key)).frame(width: 8, height: 8)
                                Text(c.key).font(.caption).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Money.text(c.value)).font(.caption.weight(.semibold).monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
    }
}

struct InOutCard: View {
    let store: BudgetStore
    struct Bar: Identifiable { let id = UUID(); let month: String; let kind: String; let value: Double }

    var body: some View {
        let cal = Calendar.current
        let bars: [Bar] = (0..<6).reversed().flatMap { i -> [Bar] in
            let d = cal.date(byAdding: .month, value: -i, to: Date())!
            let t = store.totals(year: cal.component(.year, from: d), month: cal.component(.month, from: d))
            let m = String(BudgetCats.months[cal.component(.month, from: d) - 1].prefix(3))
            return [Bar(month: m, kind: "Einnahmen", value: Double(t.inc) / 100), Bar(month: m, kind: "Ausgaben", value: Double(t.out) / 100)]
        }
        if !store.rawTx.isEmpty {
            Card {
                HStack {
                    Text("Rein und raus").font(.title3.bold())
                    Spacer()
                    Text("letzte 6 Monate").font(.caption).foregroundStyle(.secondary)
                }
                Chart(bars) { b in
                    BarMark(x: .value("Monat", b.month), y: .value("Euro", b.value))
                        .position(by: .value("Art", b.kind))
                        .foregroundStyle(by: .value("Art", b.kind))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(["Einnahmen": BudgetCats.green, "Ausgaben": BudgetCats.red])
                .frame(height: 180)
            }
        }
    }
}

// MARK: - Alle Umsätze / Umsätze eines Kontos

struct TxListView: View {
    let store: BudgetStore
    let filter: TxFilter
    enum Kind: String, CaseIterable { case all = "Alle", out = "Ausgaben", back = "Rückzahlungen", inc = "Einnahmen" }
    @State private var kind: Kind = .all
    @State private var query = ""
    @State private var openTx: Transaction?
    @State private var shown = 150

    private var list: [Transaction] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.allTx.filter { t in
            if let a = filter.account, t.acc != a { return false }
            switch kind {
            case .all: break
            case .out: if t.amount >= 0 { return false }
            case .back: if !(t.amount > 0 && store.cat(t) == BudgetCats.back) { return false }
            case .inc: if !(t.amount > 0 && store.cat(t) != BudgetCats.back) { return false }
            }
            if q.isEmpty { return true }
            return "\(t.name) \(t.text) \(store.label(t)) \(store.cat(t))".lowercased().contains(q)
        }
        .sorted { $0.date != $1.date ? $0.date > $1.date : abs($0.amount) > abs($1.amount) }
    }

    var body: some View {
        let l = list
        let months = Dictionary(grouping: l.prefix(shown), by: { String($0.date.prefix(7)) }).sorted { $0.key > $1.key }
        List {
            if let a = filter.account.flatMap({ store.accounts[$0] }) {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(a.subtitle) · \(a.name)").font(.caption).foregroundStyle(.secondary)
                        Text(a.balance.map { Money.text($0) } ?? "–").font(.title.bold())
                    }
                }
            }
            Section {
                Picker("Art", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(months, id: \.key) { m, items in
                let p = m.split(separator: "-").compactMap { Int($0) }
                let out = items.filter { $0.amount < 0 && !$0.ex && !BudgetCats.noSpend.contains(store.cat($0)) }.reduce(0) { $0 - $1.amount }
                Section {
                    ForEach(items) { t in
                        TxRow(store: store, tx: t, showDate: true)
                            .listRowInsets(EdgeInsets())
                            .onTapGesture { openTx = t }
                    }
                } header: {
                    HStack {
                        Text(p.count == 2 ? "\(BudgetCats.months[p[1] - 1]) \(p[0])" : m)
                        Spacer()
                        Text("ausgegeben \(Money.text(out))").textCase(nil)
                    }
                }
            }
            if l.count > shown {
                Button("Mehr anzeigen") { shown += 150 }.frame(maxWidth: .infinity)
            }
            if l.isEmpty {
                Text(query.isEmpty ? "Noch keine Umsätze." : "Nichts gefunden.").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "Name, Zweck, Kategorie")
        .refreshable { await store.refresh() }
        .navigationTitle(filter.account.flatMap { store.accounts[$0]?.name } ?? "Alle Umsätze")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openTx) { t in TxSheet(store: store, tx: t) }
    }
}

// MARK: - Umsatz bearbeiten

struct TxSheet: View {
    let store: BudgetStore
    let tx: Transaction
    @Environment(\.dismiss) private var dismiss
    @State private var cat = ""
    @State private var name = ""
    @State private var remember = true
    @State private var exclude = false
    @State private var editManual = false
    @State private var filled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Money.signed(tx.amount)).font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(tx.amount > 0 ? BudgetCats.green : Color.primary)
                        Text("\(Gym.date(tx.date).formatted(.dateTime.weekday(.wide).day().month(.wide).year()))\(tx.acc.flatMap { store.accounts[$0]?.name }.map { " · \($0)" } ?? "")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                if let p = store.pairInfo(tx) {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Wird nicht doppelt gezählt").font(.headline)
                            Text(pairText(p)).font(.subheadline).foregroundStyle(.secondary)
                            Button("Trotzdem mitzählen") { store.setKeep(tx, true); dismiss() }.font(.subheadline.weight(.semibold))
                        }
                    }
                } else if store.ppKeep.contains(tx.id) {
                    Section {
                        Button("Wieder nicht doppelt zählen") { store.setKeep(tx, false); dismiss() }
                    } footer: { Text("Wird mitgezählt, obwohl es nach einer doppelten PayPal-Buchung aussieht.") }
                }
                if tx.src == "manual" {
                    Section {
                        Button("Ausgabe bearbeiten") { editManual = true }
                    } footer: { Text("Von Hand eingetragen.") }
                }
                if tx.src != "manual" {
                    Section("Name") { TextField("Name", text: $name) }
                    Section {
                        Toggle("Für alle Umsätze von „\(name.isEmpty ? store.label(tx) : name)“ merken", isOn: $remember)
                        Toggle("Nicht mitzählen", isOn: $exclude)
                    }
                    // Kategorie direkt hier wählen (Häkchen), ohne in eine eigene Liste zu springen
                    Section("Kategorie") {
                        ForEach(store.catList, id: \.self) { c in
                            Button { cat = c } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: store.symbol(c)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                        .frame(width: 28, height: 28).background(store.tint(c), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    Text(c).foregroundStyle(.primary)
                                    Spacer()
                                    if cat == c { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                }
                Section("Original") {
                    LabeledContent("Empfänger", value: tx.name.isEmpty ? "–" : tx.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verwendungszweck").font(.caption).foregroundStyle(.secondary)
                        Text(tx.text.isEmpty ? "–" : tx.text).font(.subheadline)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: cat)
            .navigationTitle(store.label(tx))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if tx.src != "manual" {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            store.saveTx(tx, cat: cat, exclude: exclude, remember: remember, name: name.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        }
                    }
                }
            }
            // nur beim ersten Öffnen füllen – nach der Kategorie-Auswahl erscheint das Formular erneut
            .onAppear { if !filled { filled = true; cat = store.cat(tx); name = store.label(tx); exclude = tx.ex } }
            .sheet(isPresented: $editManual, onDismiss: { dismiss() }) { ExpenseSheet(store: store, tx: tx) }
        }
    }

    private func pairText(_ p: (with: Transaction?, kind: String)) -> String {
        switch p.kind {
        case "bank":
            if let w = p.with {
                let rest = -w.amount > -tx.amount ? " Den Rest hast du mit PayPal-Guthaben bezahlt." : ""
                return "Dieser Betrag ist schon im PayPal-Einkauf „\(store.label(w))“ über \(Money.text(-w.amount)) vom \(Gym.date(w.date).formatted(.dateTime.day().month())) enthalten.\(rest)"
            }
            return "Dieser Betrag ist schon in einem PayPal-Einkauf enthalten."
        case "topup": return "Das ist Geld von deinem Bankkonto auf PayPal, keine Einnahme."
        default: return "Das ist eine Auszahlung zwischen PayPal und deinem Bankkonto."
        }
    }
}
