import SwiftUI
import HogarCore

struct AccountsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editor = false
    var body: some View {
        List {
            Section {
                Text("Registros manuales sin conexión bancaria. El saldo inicial no se cuenta como ingreso.").foregroundStyle(.secondary)
            }
            ForEach(store.household?.accounts ?? []) { account in
                VStack(alignment: .leading, spacing: 8) {
                    Label(account.name, systemImage: account.kind == .cash ? "banknote" : "building.columns")
                    LabeledContent("Saldo registrado", value: Money.format(store.household?.balance(account: account.id) ?? 0))
                    Text("\(account.kind.rawValue) · Inicial: \(account.opening.formatted)").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            if store.household?.accounts.isEmpty == true { ContentUnavailableView("Añade tu primera cuenta", systemImage: "wallet.pass", description: Text("Introduce el saldo al comenzar el registro. Puedes añadir efectivo y cuentas de ahorro.")) }
        }.navigationTitle("Cuentas")
        .toolbar { Button { editor = true } label: { Label("Nueva cuenta", systemImage: "plus") } }
        .sheet(isPresented: $editor) { AccountEditor() }
    }
}
private struct AccountEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = "0"
    @State private var kind: AccountKind = .bank
    var body: some View {
        NavigationStack {
            Form {
                InlineSaveError()
                TextField("Nombre", text: $name)
                Picker("Tipo", selection: $kind) { ForEach(AccountKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Saldo inicial en euros", text: $amount)
                Text("Usa coma decimal, sin separadores de miles. Se permite saldo inicial negativo.").font(.caption)
            }.formStyle(.grouped).navigationTitle("Nueva cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if store.update({ home, actor in try Ledger.addAccount(Account(name: name, kind: kind, opening: Money(amount)), to: &home, actor: actor) }) { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.frame(minWidth: 300, minHeight: 320)
    }
}
