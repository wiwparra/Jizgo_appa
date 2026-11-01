import SwiftUI
import HogarCore

struct PlansView: View {
    @EnvironmentObject private var store: AppStore
    @State private var date = Date()
    @State private var budgetEditor = false
    @State private var goalEditor = false
    @State private var selectedGoal: Goal?
    @State private var editingGoal: Goal?
    @State private var deletingGoal: Goal?
    var body: some View {
        List {
            Section("Presupuestos · \(Month(date).label)") {
                PeriodPicker(date: $date)
                ForEach((store.household?.budgets ?? []).filter { $0.month == Month(date) }) { budget in
                    if let status = store.household?.budgetStatus(budget) {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent(budget.category.rawValue, value: Money.format(status.limit))
                            Text("Consumido: \(Money.format(status.consumed)) · Restante: \(Money.format(status.remaining))").font(.callout)
                            if status.excess > 0 { Label("Exceso: \(Money.format(status.excess))", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        }.padding(.vertical, 5)
                    }
                }
                Button("Establecer límite de este mes") { budgetEditor = true }
                Text("Cada mes conserva su propio presupuesto. Cambiar un mes no modifica los anteriores.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Metas de ahorro") {
                if store.household?.goals.isEmpty == true { Text("Crea una meta y reserva dinero sin registrar un gasto.").foregroundStyle(.secondary) }
                ForEach(store.household?.goals ?? []) { goal in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(goal.name).font(.headline)
                        ProgressView(value: Float(goal.reserved.cents), total: Float(goal.target.cents)).accessibilityLabel("Progreso de \(goal.name)").accessibilityValue("\(goal.reserved.formatted) de \(goal.target.formatted)")
                        Text("\(goal.reserved.formatted) de \(goal.target.formatted)")
                        Text("Fecha: \(goal.due.formatted(date: .abbreviated, time: .omitted)) · Necesario por mes: \(Money.format(goal.requiredMonthly(on: Date())))").font(.caption)
                        if goal.overdue(on: Date()) { Label("Meta vencida", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.orange) }
                        HStack {
                            Button("Reservar o liberar") { selectedGoal = goal }
                            Button("Editar") { editingGoal = goal }
                            Button("Eliminar", role: .destructive) { deletingGoal = goal }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 8)
                }
                if let summary = store.household?.summary(month: Month(Date())), summary.uncovered > 0 {
                    Label("Faltan \(Money.format(summary.uncovered)) para cubrir las reservas. No se han ocultado los gastos.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button("Nueva meta") { goalEditor = true }
            }
        }.navigationTitle("Planificación")
        .sheet(isPresented: $budgetEditor) { BudgetEditor(month: Month(date)) }
        .sheet(isPresented: $goalEditor) { GoalEditor() }
        .sheet(item: $selectedGoal) { ReserveEditor(goal: $0) }
        .sheet(item: $editingGoal) { GoalEditor(existing: $0) }
        .confirmationDialog("¿Eliminar la meta y liberar su reserva? No cambia el saldo bancario.", isPresented: Binding(get: { deletingGoal != nil }, set: { if !$0 { deletingGoal = nil } }), titleVisibility: .visible) {
            Button("Eliminar meta", role: .destructive) {
                if let goal = deletingGoal { store.update { home, actor in try Ledger.deleteGoal(goal.id, in: &home, actor: actor) } }
                deletingGoal = nil
            }
        }
    }
}
private struct BudgetEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let month: Month
    @State private var category: Category = .alimentacion
    @State private var amount = ""
    var body: some View {
        NavigationStack {
            Form {
                InlineSaveError()
                Text("Mes: \(month.label)")
                Picker("Categoría", selection: $category) { ForEach(Category.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Límite en euros", text: $amount)
                Text("Guardar reemplaza el límite de esta categoría solo para este mes.").font(.caption)
            }.formStyle(.grouped).navigationTitle("Presupuesto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") {
                    if store.update({ home, actor in try Ledger.setBudget(Budget(month: month, category: category, limit: Money(amount)), in: &home, actor: actor) }) { dismiss() }
                } }
            }
        }.frame(minWidth: 300, minHeight: 300)
    }
}
private struct GoalEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var existing: Goal?
    @State private var name = ""
    @State private var amount = ""
    @State private var due = Date()
    var body: some View {
        NavigationStack {
            Form {
                InlineSaveError()
                TextField("Nombre de la meta", text: $name)
                TextField("Objetivo en euros", text: $amount)
                DatePicker("Fecha objetivo", selection: $due, displayedComponents: .date)
                Text("La aportación mensual incluye el mes actual y el del vencimiento. Se redondea hacia arriba al céntimo.").font(.caption)
            }.formStyle(.grouped).navigationTitle(existing == nil ? "Nueva meta" : "Editar meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") {
                    if store.update({ home, actor in
                        let goal = try Goal(id: existing?.id ?? UUID(), name: name, target: Money(amount), due: due, reserved: existing?.reserved ?? Money(cents: 0))
                        if existing != nil { try Ledger.editGoal(goal, in: &home, actor: actor) }
                        else { try Ledger.addGoal(goal, to: &home, actor: actor) }
                    }) { dismiss() }
                } }
            }
        }.frame(minWidth: 300, minHeight: 330)
        .onAppear { if let existing { name = existing.name; amount = existing.target.input; due = existing.due } }
    }
}
private struct ReserveEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var amount = ""
    @State private var release = false
    var body: some View {
        NavigationStack {
            Form {
                InlineSaveError()
                Text(goal.name).font(.headline)
                Text("Reservado: \(goal.reserved.formatted)")
                Toggle("Liberar dinero", isOn: $release)
                TextField("Importe positivo en euros", text: $amount)
                Text("Una reserva solo asigna parte del saldo a una meta. No crea un gasto ni una transferencia.").font(.caption)
            }.formStyle(.grouped).navigationTitle("Gestionar reserva")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Aplicar") {
                    if store.update({ home, actor in
                        let value = try Money(amount)
                        guard value.cents > 0 else { throw FinanceError.invalid("Introduce un importe positivo.") }
                        try Ledger.reserve(Money(cents: release ? -value.cents : value.cents), goal: goal.id, in: &home, actor: actor)
                    }) { dismiss() }
                } }
            }
        }.frame(minWidth: 300, minHeight: 330)
    }
}
