import SwiftUI
import HogarCore

struct EntriesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var date = Date()
    @State private var allMonths = false
    @State private var query = ""
    @State private var tag = ""
    @State private var bankImport = false
    @State private var category: HogarCore.Category?
    @State private var account: UUID?
    @State private var member: UUID?
    @State private var editor = false
    @State private var editing: Entry?
    @State private var deleting: Entry?
    var body: some View {
        List {
            Section("Filtros") {
                TextField("Etiqueta exacta (opcional)", text: $tag)
                Toggle("Todos los meses", isOn: $allMonths)
                if !allMonths { PeriodPicker(date: $date) }
                Picker("Categoría", selection: $category) {
                    Text("Todas").tag(nil as HogarCore.Category?)
                    ForEach(HogarCore.Category.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("Cuenta", selection: $account) {
                    Text("Todas").tag(nil as UUID?)
                    ForEach(store.household?.accounts ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Miembro atribuido", selection: $member) {
                    Text("Todos").tag(nil as UUID?)
                    ForEach(store.household?.members ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Section("Movimientos") {
                let entries = store.household?.filtered(EntryFilter(month: allMonths ? nil : Month(date), category: category, account: account, member: member, tag: tag, query: query)) ?? []
                if entries.isEmpty { ContentUnavailableView("Sin movimientos", systemImage: "list.bullet.rectangle", description: Text("Añade un movimiento o cambia los filtros.")) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.title).font(.headline)
                            Spacer()
                            Text((entry.kind == .expense ? "−" : entry.kind == .income ? "+" : "↔ ") + entry.amount.formatted).monospacedDigit()
                        }
                        Text("\(entry.kind.rawValue) · \(entry.category.rawValue) · \(entry.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        Text("Cuenta: \(store.household?.accounts.first { $0.id == entry.accountID }?.name ?? "—") · Miembro: \(store.household?.members.first { $0.id == entry.memberID }?.name ?? "—")").font(.caption)
                        Text(entry.authorID == nil ? "Autor histórico sin verificar" : "Autor: \(store.household?.members.first { $0.id == entry.authorID }?.name ?? "—")").font(.caption).foregroundStyle(.secondary)
                        if !entry.tags.isEmpty { Text("Etiquetas: " + entry.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                        if store.canEdit(entry) {
                            HStack {
                                Button("Editar") { editing = entry }
                                Button("Eliminar", role: .destructive) { deleting = entry }
                            }.buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("Movimientos").searchable(text: $query, prompt: "Concepto, notas o etiquetas")
        .toolbar {
            Button { bankImport = true } label: { Label("Desde aviso bancario", systemImage: "text.viewfinder") }.disabled(store.household?.accounts.isEmpty != false)
            Button { editing = nil; editor = true } label: { Label("Añadir", systemImage: "plus") }.disabled(store.household?.accounts.isEmpty != false)
        }
        .sheet(isPresented: $bankImport) { BankNoticeView() }
        .sheet(isPresented: $editor) { EntryEditor() }
        .sheet(item: $editing) { EntryEditor(entry: $0) }
        .confirmationDialog("¿Eliminar este movimiento? Se recalcularán los saldos.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Eliminar movimiento", role: .destructive) {
                if let deleting { store.update { home, actor in try Ledger.deleteEntry(deleting.id, in: &home, actor: actor, expectedRevision: deleting.revision) } }
                deleting = nil
            }
        }
    }
}
struct EntryEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var entry: Entry?
    @State private var kind: EntryKind = .expense
    @State private var amount = ""
    @State private var title = ""
    @State private var notes = ""
    @State private var tagInput = ""
    @State private var date = Date()
    @State private var category: HogarCore.Category = .alimentacion
    @State private var account: UUID?
    @State private var destination: UUID?
    @State private var member: UUID?
    var body: some View {
        NavigationStack {
            Form {
                InlineSaveError()
                Picker("Tipo", selection: $kind) { ForEach(EntryKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Importe en euros (12,50)", text: $amount)
                TextField("Concepto", text: $title)
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                Picker("Cuenta de origen", selection: $account) { ForEach(store.household?.accounts ?? []) { Text($0.name).tag(Optional($0.id)) } }
                if kind == .transfer {
                    Picker("Cuenta de destino", selection: $destination) { Text("Selecciona").tag(nil as UUID?); ForEach((store.household?.accounts ?? []).filter { $0.id != account }) { Text($0.name).tag(Optional($0.id)) } }
                } else {
                    Picker("Categoría", selection: $category) { ForEach(HogarCore.Category.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                Picker("Atribuido a", selection: $member) { ForEach((store.household?.members ?? []).filter { $0.active || $0.id == entry?.memberID }) { Text($0.name).tag(Optional($0.id)) } }
                Text(store.familyEnabled ? "El autor es tu cuenta autenticada. Atribuir un movimiento no cambia quién lo registró." : "El autor es la identidad local de este dispositivo. Atribuir un movimiento no cambia su autor.").font(.caption)
                TextField("Etiquetas separadas por comas", text: $tagInput)
                Text("Ejemplo: compra semanal, vacaciones, colegio. Las etiquetas son independientes de la categoría.").font(.caption).foregroundStyle(.secondary)
                TextField("Notas", text: $notes, axis: .vertical)
            }.formStyle(.grouped).navigationTitle(entry == nil ? "Nuevo movimiento" : "Editar movimiento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(account == nil || member == nil || title.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty) }
            }
        }.frame(minWidth: 300, minHeight: 500)
        .onAppear {
            if let entry { kind = entry.kind; amount = entry.amount.input; title = entry.title; notes = entry.notes; tagInput = entry.tags.joined(separator: ", "); date = entry.date; category = entry.category; account = entry.accountID; destination = entry.destinationID; member = entry.memberID }
            else { account = store.household?.accounts.first?.id; member = store.actor }
        }
    }
    private func save() {
        guard let account, let member else { return }
        if store.update({ home, actor in
            let value = Entry(id: entry?.id ?? UUID(), authorID: entry == nil ? actor : entry!.authorID, memberID: member, accountID: account, destinationID: kind == .transfer ? destination : nil, kind: kind, amount: try Money(amount), date: date, category: category, title: title, notes: notes, tags: try EntryTags.parse(tagInput), revision: entry?.revision ?? 0)
            try Ledger.putEntry(value, in: &home, actor: actor, expectedRevision: entry?.revision)
        }) { dismiss() }
    }
}
