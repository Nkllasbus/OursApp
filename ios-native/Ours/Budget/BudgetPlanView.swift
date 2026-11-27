import SwiftUI

// MARK: - Budgets (Gehalt einteilen)

struct BudgetPlanView: View {
    let store: BudgetStore
    @Binding var openTx: Transaction?
    @State private var openCat: String?
    @State private var newBudget = false
    @State private var editSalary = false
    @State private var editIncome: ExtraIncome?
    @State private var newIncome = false

    var body: some View {
        let si = store.salaryInfo(), spend = store.periodSpend(si), inc = store.income(si)
        let planned = store.budgets.values.reduce(0, +)
        let spentB = store.budgets.keys.reduce(0) { $0 + (spend[$1] ?? 0) }
        let free = inc.total - planned
        let cats = Array(Set(store.budgets.keys).union(spend.keys))
            .filter { !BudgetCats.income.contains($0) && !BudgetCats.noSpend.contains($0) }
            .sorted { ((store.budgets[$0] != nil ? 0 : 1), -(spend[$0] ?? 0)) < ((store.budgets[$1] != nil ? 0 : 1), -(spend[$1] ?? 0)) }
        VStack(spacing: 16) {
            Card {
                Text("ZUM EINTEILEN").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(Money.text(inc.total)).font(.system(size: 36, weight: .bold))
                Button { editSalary = true } label: {
                    HStack {
                        Text("💰 \(si.fromSalary ? "Gehalt" : "Einkommen")\(si.manual ? " (eigener Betrag)" : "")").foregroundStyle(.primary)
                        Spacer()
                        Text(si.amount > 0 ? Money.text(si.amount) : "eintragen").bold().foregroundStyle(.primary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
                ForEach(inc.extra) { x in
                    Button { editIncome = x } label: {
                        HStack {
                            Text("➕ \(x.n)").foregroundStyle(.primary)
                            Text(x.monthly ? "jeden Monat" : "nur dieser Zeitraum").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(Money.text(x.a)).bold().foregroundStyle(.primary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                    }
                }
                Button { newIncome = true } label: { Label("Weitere Einnahme hinzufügen", systemImage: "plus").font(.subheadline.weight(.semibold)) }
                Text("\(si.fromSalary ? "Zeitraum" : "Monat") \(Gym.date(si.start).formatted(.dateTime.day().month())) – \(Gym.date(si.end).formatted(.dateTime.day().month())) · noch \(si.daysLeft) \(si.daysLeft == 1 ? "Tag" : "Tage")")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StatTile(value: Money.text(planned), label: "Eingeteilt")
                    StatTile(value: Money.text(spentB), label: "Ausgegeben")
                    StatTile(value: Money.text(abs(free)), label: free < 0 ? "Zu viel eingeteilt" : "Noch frei")
                }
                if inc.total > 0 {
                    ProgressView(value: min(1, Double(planned) / Double(inc.total))).tint(OursPage.budget.color)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Kategorien").font(.title3.bold())
                    Spacer()
                    Button { newBudget = true } label: { Label("Budget", systemImage: "plus") }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
                if cats.isEmpty { Text("Noch keine Ausgaben in diesem Zeitraum.").foregroundStyle(.secondary) }
                ForEach(cats, id: \.self) { c in
                    let b = store.budgets[c] ?? 0, v = spend[c] ?? 0
                    Button { openCat = c } label: { BudgetRow(store: store, cat: c, budget: b, spent: v, daysLeft: si.daysLeft) }
                        .buttonStyle(PressStyle())
                }
            }
            Text("Bei 80 % und 100 % eines Budgets bekommst du eine Mitteilung (über die Webseite eingerichtet).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: Binding(get: { openCat.map { CatRef(id: $0) } }, set: { openCat = $0?.id })) { ref in
            CategorySheet(store: store, cat: ref.id, openTx: $openTx)
        }
        .sheet(isPresented: $newBudget) { BudgetEditSheet(store: store, cat: nil) }
        .sheet(isPresented: $editSalary) { SalarySheet(store: store) }
        .sheet(item: $editIncome) { x in IncomeSheet(store: store, income: x) }
        .sheet(isPresented: $newIncome) { IncomeSheet(store: store, income: nil) }
    }
}

struct CatRef: Identifiable { let id: String }

struct BudgetRow: View {
    let store: BudgetStore
    let cat: String
    let budget: Int
    let spent: Int
    let daysLeft: Int

    var body: some View {
        let lv = budget == 0 ? 0 : spent >= budget ? 2 : Double(spent) >= Double(budget) * 0.8 ? 1 : 0
        let col: Color = lv == 2 ? .red : lv == 1 ? .orange : Color(hex: store.color(cat))
        let left = budget - spent
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color(hex: store.color(cat))).frame(width: 9, height: 9)
                Text(cat).foregroundStyle(.primary)
                Spacer()
                Text(Money.text(spent)).bold().foregroundStyle(.primary)
                if budget > 0 { Text("/ \(Money.text(budget))").foregroundStyle(.secondary) }
            }
            .font(.body.monospacedDigit())
            if budget > 0 {
                ProgressView(value: min(1, Double(spent) / Double(budget))).tint(col)
            }
            Text(budget == 0 ? "Kein Budget festgelegt"
                 : lv == 2 ? "\(Money.text(-left)) über dem Budget"
                 : "noch \(Money.text(left))\(left > 0 ? " · \(Money.text(left / max(1, daysLeft))) pro Tag" : "")\(lv == 1 ? " · fast aufgebraucht" : "")")
                .font(.caption).foregroundStyle(lv == 2 ? Color.red : Color.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Kategorie antippen: Abbuchungen im Zeitraum und Korrekturen
struct CategorySheet: View {
    let store: BudgetStore
    let cat: String
    @Binding var openTx: Transaction?
    @Environment(\.dismiss) private var dismiss
    @State private var editAdj: BudgetAdjustment?
    @State private var newAdj = false
    @State private var editBudget = false
    @State private var showTx: Transaction?

    var body: some View {
        let si = store.salaryInfo(), b = store.budgets[cat] ?? 0
        let list = store.periodTx(si, cat: cat)
        let raw = list.reduce(0) { $0 - $1.amount }
        let adj = store.adjustments(si, cat: cat), adjSum = adj.reduce(0) { $0 + $1.a }
        let v = max(0, raw - adjSum)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Money.text(v)).font(.system(size: 34, weight: .bold))
                            Text(b > 0 ? "von \(Money.text(b)) Budget" : "ausgegeben").foregroundStyle(.secondary)
                        }
                        if b > 0 {
                            ProgressView(value: min(1, Double(v) / Double(b))).tint(v >= b ? .red : Color(hex: store.color(cat)))
                            Text(v >= b ? "\(Money.text(v - b)) über dem Budget" : "Noch \(Money.text(b - v)) frei")
                                .font(.subheadline.weight(v >= b ? .semibold : .regular)).foregroundStyle(v >= b ? Color.red : Color.secondary)
                        }
                        Text("Zeitraum \(Gym.date(si.start).formatted(.dateTime.day().month())) – \(Gym.date(si.end).formatted(.dateTime.day().month()))\(adj.isEmpty ? "" : " · \(Money.text(raw)) abgebucht \(adjSum >= 0 ? "−" : "+") \(Money.text(abs(adjSum))) Korrekturen")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Korrekturen") {
                    ForEach(adj) { a in
                        Button { editAdj = a } label: {
                            HStack {
                                Image(systemName: a.a > 0 ? "arrow.uturn.backward.circle.fill" : "plus.circle.fill")
                                    .foregroundStyle(a.a > 0 ? Color.green : Color.secondary).font(.title3)
                                VStack(alignment: .leading) {
                                    Text(a.n ?? (a.a > 0 ? "Geld zurück" : "Ausgabe dazu")).foregroundStyle(.primary)
                                    Text(Gym.date(a.d).formatted(.dateTime.weekday(.abbreviated).day().month())).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(a.a > 0 ? "−" : "+")\(Money.text(abs(a.a)))").monospacedDigit().foregroundStyle(a.a > 0 ? Color.green : Color.primary)
                            }
                        }
                    }
                    Button { newAdj = true } label: { Label(adj.isEmpty ? "Betrag hinzufügen oder abziehen" : "Weitere Korrektur", systemImage: "plus") }
                }
                let days = Dictionary(grouping: list, by: \.date).sorted { $0.key > $1.key }
                ForEach(days, id: \.key) { d, items in
                    Section(dayLabel(d)) {
                        ForEach(items) { t in
                            TxRow(store: store, tx: t).listRowInsets(EdgeInsets()).onTapGesture { showTx = t }
                        }
                    }
                }
                if list.isEmpty {
                    Text("In diesem Zeitraum gibt es noch keine Abbuchungen in „\(cat)“.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(cat)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(b > 0 ? "Budget ändern" : "Budget festlegen") { editBudget = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .sheet(item: $editAdj) { a in AdjustmentSheet(store: store, cat: cat, adj: a) }
            .sheet(isPresented: $newAdj) { AdjustmentSheet(store: store, cat: cat, adj: nil) }
            .sheet(isPresented: $editBudget) { BudgetEditSheet(store: store, cat: cat) }
            .sheet(item: $showTx) { t in TxSheet(store: store, tx: t) }
        }
    }
}

struct AdjustmentSheet: View {
    let store: BudgetStore
    let cat: String
    let adj: BudgetAdjustment?
    @Environment(\.dismiss) private var dismiss
    @State private var back = true
    @State private var amount = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var linked: String?
    @State private var confirmDelete = false

    var body: some View {
        let si = store.salaryInfo()
        let linkedIDs = Set(store.adj.values.compactMap(\.tx))
        let sug = adj == nil ? store.allTx.filter { $0.amount > 0 && !$0.ex && $0.date >= si.start && $0.date <= si.end && !linkedIDs.contains($0.id)
            && [BudgetCats.back, "Sonstige Einnahmen"].contains(store.cat($0)) }.sorted { $0.date > $1.date }.prefix(6) : []
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $back) {
                        Text("Geld zurück").tag(true)
                        Text("Ausgabe dazu").tag(false)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(back ? "Zieht den Betrag von „\(cat)“ ab, z. B. wenn dir Freunde Geld zurückgegeben haben." : "Rechnet den Betrag zu „\(cat)“ dazu, z. B. wenn du bar bezahlt hast.")
                }
                if !sug.isEmpty {
                    Section("Eingegangen in diesem Zeitraum") {
                        ForEach(Array(sug)) { t in
                            Button {
                                linked = linked == t.id ? nil : t.id
                                if linked != nil {
                                    amount = String(format: "%.2f", Double(t.amount) / 100).replacingOccurrences(of: ".", with: ",")
                                    if note.isEmpty { note = "Von \(store.label(t))" }
                                    date = Gym.date(t.date); back = true
                                }
                            } label: {
                                HStack {
                                    Image(systemName: linked == t.id ? "checkmark.circle.fill" : "circle").foregroundStyle(OursPage.budget.color)
                                    Text(store.label(t)).foregroundStyle(.primary)
                                    Spacer()
                                    Text(Money.text(t.amount)).bold().foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                Section("Betrag") {
                    HStack {
                        Text(back ? "−" : "+").font(.title2.bold()).foregroundStyle(.secondary)
                        TextField("0,00", text: $amount).keyboardType(.decimalPad).font(.title2.bold())
                        Text("€").foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField(back ? "z. B. Von Freunden fürs Kino" : "z. B. Bar bezahlt", text: $note)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }
                if adj != nil {
                    Section { Button("Löschen", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(adj == nil ? "Betrag anpassen" : "Korrektur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let c = Money.parse(amount) else { return }
                        store.saveAdjustment(id: adj?.id, cat: cat, cents: back ? c : -c, note: note.trimmingCharacters(in: .whitespaces),
                                             date: Gym.iso(date), tx: linked)
                        dismiss()
                    }
                    .disabled(Money.parse(amount) == nil)
                }
            }
            .confirmationDialog("Korrektur löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { if let adj { store.deleteAdjustment(adj) }; dismiss() }
            }
            .onAppear {
                if let a = adj {
                    back = a.a > 0; note = a.n ?? ""; date = Gym.date(a.d); linked = a.tx
                    amount = String(format: "%.2f", Double(abs(a.a)) / 100).replacingOccurrences(of: ".", with: ",")
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct BudgetEditSheet: View {
    let store: BudgetStore
    let cat: String?
    @Environment(\.dismiss) private var dismiss
    @State private var pick = ""
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                if cat == nil {
                    Section("Kategorie") {
                        Picker("Kategorie", selection: $pick) {
                            ForEach(store.catList.filter { !BudgetCats.income.contains($0) && !BudgetCats.noSpend.contains($0) }, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("0", text: $amount).keyboardType(.decimalPad).font(.title2.bold())
                        Text("€").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Budget bis zum nächsten Gehalt")
                }
                if let cat, store.budgets[cat] != nil {
                    Section { Button("Budget entfernen", role: .destructive) { store.setBudget(cat, cents: nil); dismiss() } }
                }
            }
            .navigationTitle(cat ?? "Budget festlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let c = cat ?? pick
                        guard !c.isEmpty, let v = Money.parse(amount) else { return }
                        store.setBudget(c, cents: v); dismiss()
                    }
                    .disabled((cat ?? pick).isEmpty || Money.parse(amount) == nil)
                }
            }
            .onAppear {
                pick = store.catList.first ?? ""
                if let cat, let b = store.budgets[cat] { amount = String(format: "%.2f", Double(b) / 100).replacingOccurrences(of: ".", with: ",") }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Verträge

struct ContractsView: View {
    let store: BudgetStore
    @State private var open: Contract?

    var body: some View {
        let list = store.contracts()
        let pm = list.reduce(0) { $0 + $1.perMonth }
        VStack(alignment: .leading, spacing: 10) {
            Card {
                Text("VERTRÄGE & ABOS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(Money.text(pm)) pro Monat").font(.system(size: 30, weight: .bold))
                Text("\(list.count) erkannt aus wiederkehrenden Abbuchungen").font(.caption).foregroundStyle(.secondary)
            }
            if list.isEmpty { Text("Noch keine wiederkehrenden Abbuchungen erkannt.").foregroundStyle(.secondary) }
            ForEach(list) { c in
                Button { open = c } label: {
                    HStack(spacing: 12) {
                        Text(String(c.name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color(hex: store.color(c.cat)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(c.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                if c.isNew { Text("neu").font(.caption2.bold()).foregroundStyle(.blue) }
                                if c.raise != nil { Text("teurer").font(.caption2.bold()).foregroundStyle(.orange) }
                            }
                            Text("\(c.rhythmLabel) · nächste \(c.next.formatted(.dateTime.day().month()))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.text(c.avg)).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
        .sheet(item: $open) { c in ContractSheet(store: store, contract: c) }
    }
}

struct ContractSheet: View {
    let store: BudgetStore
    let contract: Contract
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Betrag", value: Money.text(contract.avg))
                    LabeledContent("Rhythmus", value: contract.rhythmLabel)
                    LabeledContent("Pro Monat", value: Money.text(contract.perMonth))
                    LabeledContent("Nächste Abbuchung", value: contract.next.formatted(.dateTime.weekday(.abbreviated).day().month()))
                    LabeledContent("Kategorie", value: contract.cat)
                    if let r = contract.raise {
                        Text("Preis gestiegen: \(Money.text(r.from)) → \(Money.text(r.to))").foregroundStyle(.orange)
                    }
                }
                Section("Bisherige Abbuchungen") {
                    ForEach(contract.txs) { t in TxRow(store: store, tx: t, showDate: true).listRowInsets(EdgeInsets()) }
                }
                Section {
                    Button("Ist kein Vertrag – ausblenden", role: .destructive) { store.hideContract(contract); dismiss() }
                }
            }
            .navigationTitle(contract.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

// MARK: - Analyse

struct BudgetStatsView: View {
    let store: BudgetStore
    @Binding var openTx: Transaction?
    @State private var offset = 0
    @State private var openCat: String?

    var body: some View {
        let cal = Calendar.current
        let d = cal.date(byAdding: .month, value: offset, to: Date())!
        let y = cal.component(.year, from: d), m = cal.component(.month, from: d)
        let t = store.totals(year: y, month: m)
        let cats = t.byCat.sorted { $0.value > $1.value }
        let mx = max(1, cats.first?.value ?? 1)
        VStack(spacing: 14) {
            HStack {
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text("\(BudgetCats.months[m - 1]) \(String(y))").font(.headline)
                Spacer()
                Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0)
            }
            .font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                StatTile(value: Money.text(t.inc), label: "Einnahmen")
                StatTile(value: Money.text(t.out), label: "Ausgaben")
                StatTile(value: Money.text(t.left), label: t.left >= 0 ? "Übrig" : "Minus")
            }
            Card {
                Text("Nach Kategorie").font(.headline)
                if cats.isEmpty { Text("Keine Ausgaben in diesem Monat.").foregroundStyle(.secondary) }
                ForEach(cats, id: \.key) { c in
                    Button { openCat = c.key } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(c.key).foregroundStyle(.primary)
                                Spacer()
                                Text(Money.text(c.value)).bold().monospacedDigit().foregroundStyle(.primary)
                            }
                            GeometryReader { g in
                                Capsule().fill(Color(hex: store.color(c.key)))
                                    .frame(width: max(6, g.size.width * CGFloat(c.value) / CGFloat(mx)), height: 7)
                            }
                            .frame(height: 7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: Binding(get: { openCat.map { CatRef(id: $0) } }, set: { openCat = $0?.id })) { ref in
            NavigationStack {
                List {
                    ForEach((t.txByCat[ref.id] ?? []).sorted { $0.date > $1.date }) { x in
                        TxRow(store: store, tx: x, showDate: true).listRowInsets(EdgeInsets())
                    }
                }
                .navigationTitle(ref.id)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}
