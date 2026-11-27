import SwiftUI
import AuthenticationServices
import UniformTypeIdentifiers

// MARK: - Ausgabe von Hand eintragen

struct ExpenseSheet: View {
    let store: BudgetStore
    let tx: Transaction?
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var title = ""
    @State private var cat = "Lebensmittel"
    @State private var date = Date()
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Betrag") {
                    HStack {
                        TextField("0,00", text: $amount).keyboardType(.decimalPad).font(.title2.bold())
                        Text("€").foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Wofür, z. B. Wocheneinkauf", text: $title)
                    Picker("Kategorie", selection: $cat) {
                        ForEach(store.catList.filter { !BudgetCats.income.contains($0) && !BudgetCats.noSpend.contains($0) }, id: \.self) { Text($0).tag($0) }
                    }
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                } footer: {
                    Text("Zum Beispiel für Barzahlungen. Die Ausgabe zählt wie ein Umsatz vom Konto.")
                }
                if tx != nil {
                    Section { Button("Löschen", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(tx == nil ? "Neue Ausgabe" : "Ausgabe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let c = Money.parse(amount) else { return }
                        store.saveExpense(id: tx?.id, cents: c, title: title.trimmingCharacters(in: .whitespaces), cat: cat, date: Gym.iso(date))
                        dismiss()
                    }
                    .disabled(Money.parse(amount) == nil)
                }
            }
            .confirmationDialog("Ausgabe löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { if let tx { store.deleteExpense(tx) }; dismiss() }
            }
            .onAppear {
                if let t = tx {
                    amount = String(format: "%.2f", Double(-t.amount) / 100).replacingOccurrences(of: ".", with: ",")
                    title = t.name; cat = t.cat ?? "Sonstiges"; date = Gym.date(t.date)
                }
            }
        }
    }
}

// MARK: - Gehalt und weitere Einnahmen

struct SalarySheet: View {
    let store: BudgetStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    var body: some View {
        let si = store.salaryInfo(), auto = store.autoSalary()
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(auto > 0 ? String(auto / 100) : "0", text: $amount).keyboardType(.decimalPad).font(.title2.bold())
                        Text("€").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Gehalt")
                } footer: {
                    Text(auto > 0 ? "Ours hat zuletzt \(Money.text(auto)) Gehalt erkannt. Trag einen eigenen Betrag ein, z. B. wenn dein Gehalt schwankt." : "Ours hat noch kein Gehalt erkannt. Trag deinen Betrag ein.")
                }
                if si.manual {
                    Section { Button("Automatisch erkennen") { store.setSalary(nil); dismiss() } }
                }
            }
            .navigationTitle("Gehalt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { store.setSalary(Money.parse(amount)); dismiss() } }
            }
            .onAppear { if si.manual { amount = String(format: "%.2f", Double(si.amount) / 100).replacingOccurrences(of: ".", with: ",") } }
        }
        .presentationDetents([.medium])
    }
}

struct IncomeSheet: View {
    let store: BudgetStore
    let income: ExtraIncome?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var monthly = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. Nebenjob, Kindergeld", text: $name)
                    HStack {
                        TextField("0,00", text: $amount).keyboardType(.decimalPad).font(.title3.bold())
                        Text("€").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Der Betrag erhöht, was du einteilen kannst.")
                }
                Section {
                    Picker("Wie oft?", selection: $monthly) {
                        Text("Jeden Monat").tag(true)
                        Text("Nur diesen Zeitraum").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if let income {
                    Section { Button("Entfernen", role: .destructive) { store.deleteIncome(income); dismiss() } }
                }
            }
            .navigationTitle(income == nil ? "Weitere Einnahme" : "Einnahme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        guard let c = Money.parse(amount) else { return }
                        store.saveIncome(id: income?.id, name: name.trimmingCharacters(in: .whitespaces), cents: c, monthly: monthly)
                        dismiss()
                    }
                    .disabled(Money.parse(amount) == nil)
                }
            }
            .onAppear {
                if let x = income { name = x.n; monthly = x.monthly; amount = String(format: "%.2f", Double(x.a) / 100).replacingOccurrences(of: ".", with: ",") }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Bank verbinden

struct BankConnectSheet: View {
    let store: BudgetStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var banks: [BudgetStore.BankOption] = []
    @State private var query = ""
    @State private var loading = true
    @State private var busy: String?
    @State private var errorText: String?
    @State private var result: BudgetStore.BankResult?
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if let r = result {
                    Form {
                        Section {
                            ForEach(r.accounts) { a in
                                Toggle(isOn: Binding(get: { picked.contains(a.uid) }, set: { on in if on { picked.insert(a.uid) } else { picked.remove(a.uid) } })) {
                                    VStack(alignment: .leading) {
                                        Text(a.name.isEmpty ? "Konto" : a.name)
                                        Text(maskIBAN(a.iban) ?? a.product ?? "").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if r.accounts.isEmpty { Text("Die Bank hat keine Konten geliefert.").foregroundStyle(.secondary) }
                        } header: {
                            Text("Welche Konten sollen in Ours erscheinen?")
                        } footer: {
                            if let v = r.validUntil, let d = ISO8601DateFormatter().date(from: v) {
                                Text("Freigabe gültig bis \(d.formatted(.dateTime.day().month().year())). Danach bestätigst du sie neu.")
                            }
                        }
                    }
                } else {
                    List {
                        Section {
                            Label("Deine Zugangsdaten gibst du nur auf der Seite deiner Bank ein. Ours bekommt nur Lesezugriff auf Kontostand und Umsätze.", systemImage: "lock.fill")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if loading { ProgressView().frame(maxWidth: .infinity) }
                        if let errorText { Text(errorText).foregroundStyle(.red) }
                        let q = query.lowercased()
                        ForEach(banks.filter { q.isEmpty || $0.name.lowercased().contains(q) }.prefix(80)) { b in
                            Button { connect(b) } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: b.logo.flatMap(URL.init(string:))) { img in img.resizable().scaledToFit() } placeholder: {
                                        Image(systemName: "building.columns").foregroundStyle(.secondary)
                                    }
                                    .frame(width: 30, height: 30)
                                    Text(b.name).foregroundStyle(.primary)
                                    Spacer()
                                    if busy == b.name { ProgressView() }
                                }
                            }
                            .disabled(busy != nil)
                        }
                    }
                    .searchable(text: $query, prompt: "Bank suchen, z. B. Sparkasse, ING, PayPal")
                }
            }
            .navigationTitle(result == nil ? "Konto verbinden" : "\(result?.bank ?? "Bank") verbunden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if let r = result {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Übernehmen") {
                            let p = picked
                            dismiss()
                            Task { await store.savePicked(r, picked: p) }
                        }
                        .disabled(picked.isEmpty)
                    }
                }
            }
            .task {
                do { banks = try await store.banks() } catch { errorText = error.localizedDescription }
                loading = false
            }
        }
    }

    private func maskIBAN(_ i: String?) -> String? {
        guard let i = i?.replacingOccurrences(of: " ", with: ""), i.count > 8 else { return i }
        return "\(i.prefix(4)) •••• \(i.suffix(4))"
    }

    private func connect(_ b: BudgetStore.BankOption) {
        busy = b.name; errorText = nil
        Task {
            defer { busy = nil }
            do {
                let start = try await store.startBank(b)
                // Anmeldung bei der Bank; die Webseite reicht die Rückmeldung an ours://bank weiter
                let back = try await webAuth.authenticate(using: start.url, callbackURLScheme: "ours", preferredBrowserSession: .ephemeral)
                let items = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                if q("error") != nil { errorText = "Die Verbindung wurde abgebrochen" + (q("error_description").map { ": \($0)" } ?? "."); return }
                guard q("state") == start.state, let code = q("code") else { errorText = "Die Rückmeldung der Bank konnte nicht bestätigt werden. Versuch es nochmal."; return }
                let r = try await store.finishBank(code: code)
                picked = Set(r.accounts.map(\.uid))
                result = r
            } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
                // abgebrochen
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - CSV importieren

struct CSVImportSheet: View {
    let store: BudgetStore
    let data: BudgetStore.CSVData
    @Environment(\.dismiss) private var dismiss
    @State private var csv: BudgetStore.CSVData
    @State private var account = "__new"
    @State private var newName = ""
    @State private var balance = ""
    @State private var busy = false

    init(store: BudgetStore, data: BudgetStore.CSVData) {
        self.store = store; self.data = data
        _csv = State(initialValue: data)
    }

    private var accounts: [BankAccount] { store.accounts.values.filter { $0.src != "eb" }.sorted { $0.name < $1.name } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(csv.body.count) Zeilen gefunden\(csv.paypal ? " · PayPal erkannt" : "")").font(.subheadline)
                }
                Section("Spalten") {
                    column("Datum", "date"); column("Betrag", "amount"); column("Name", "name"); column("Zweck", "text")
                }
                Section("Vorschau") {
                    ForEach(Array(csv.body.prefix(4).enumerated()), id: \.offset) { _, r in
                        let d = BudgetStore.parseDate(cell(r, "date")), v = BudgetStore.parseAmount(cell(r, "amount"))
                        HStack {
                            VStack(alignment: .leading) {
                                Text(cell(r, "name")).lineLimit(1)
                                Text(d ?? "Datum?").font(.caption).foregroundStyle(d == nil ? Color.red : Color.secondary)
                            }
                            Spacer()
                            Text(v.map { Money.signed($0) } ?? "?").foregroundStyle(v == nil ? Color.red : Color.primary).monospacedDigit()
                        }
                    }
                }
                Section("In welches Konto?") {
                    Picker("Konto", selection: $account) {
                        ForEach(accounts) { Text($0.name).tag($0.id) }
                        Text("Neues Konto …").tag("__new")
                    }
                    if account == "__new" { TextField("Name, z. B. PayPal", text: $newName) }
                    TextField("Aktueller Kontostand (optional)", text: $balance).keyboardType(.numbersAndPunctuation)
                }
                if csv.paypal {
                    Section { Text("PayPal-Zeilen wie „Bankgutschrift“ werden als Umbuchung markiert, damit nichts doppelt zählt.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("CSV importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") {
                        busy = true
                        Task {
                            let r = await store.importCSV(csv, account: account == "__new" ? nil : account, newName: newName,
                                                          balance: BudgetStore.parseSigned(balance))
                            store.message = "\(r.0) Umsätze importiert\(r.1 > 0 ? ", \(r.1) übersprungen (doppelt oder leer)" : "")."
                            dismiss()
                        }
                    }
                    .disabled(busy)
                }
            }
            .onAppear {
                newName = csv.accName
                if let m = accounts.first(where: { !csv.accName.isEmpty && $0.name == csv.accName }) { account = m.id }
            }
        }
    }

    private func cell(_ r: [String], _ k: String) -> String {
        let i = csv.map[k] ?? -1
        return i >= 0 && i < r.count ? r[i] : ""
    }

    private func column(_ title: String, _ k: String) -> some View {
        Picker(title, selection: Binding(get: { csv.map[k] ?? -1 }, set: { csv.map[k] = $0 })) {
            Text("–").tag(-1)
            ForEach(Array(csv.head.enumerated()), id: \.offset) { i, h in Text(h.isEmpty ? "Spalte \(i + 1)" : h).tag(i) }
        }
    }
}
