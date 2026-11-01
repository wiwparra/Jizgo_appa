import SwiftUI
import Charts
import HogarCore

struct PeriodPicker: View {
    @Binding var date: Date
    // Adaptado de MonthPicker del prototipo 0.1, con calendario explícito de Madrid.
    var body: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Mes anterior")
            Spacer()
            Text(date.formatted(.dateTime.month(.wide).year())).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Mes siguiente")
        }.buttonStyle(.borderless)
    }
    private func shift(_ offset: Int) { date = Calendar.household.date(byAdding: .month, value: offset, to: date) ?? date }

}
struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var date = Date()
    @State private var add = false
    var body: some View {
        ScrollView {
            if let home = store.household {
                let summary = home.summary(month: Month(date))
                VStack(alignment: .leading, spacing: 24) {
                    PeriodPicker(date: $date)
                    Text("Tu hogar, en perspectiva").font(.largeTitle.bold())
                    Text("Periodo: \(Month(date).label) · EUR").foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], spacing: 16) {
                        metric("Saldo registrado", summary.balance, "Saldos iniciales más todos los movimientos, a cualquier fecha.")
                        metric("Ingresos del periodo", summary.income, "Excluye saldos iniciales y transferencias.")
                        metric("Gastos del periodo", summary.expenses, "Gastos registrados durante el mes seleccionado.")
                        metric("Resultado del periodo", summary.result, "Ingresos menos gastos del mes.")
                        metric("Reservado para metas", summary.reserved, "Asignaciones virtuales; no mueven dinero bancario.")
                        metric("Saldo sin reservar", summary.unreserved, "Saldo total menos reservas. No descuenta compromisos futuros.")
                    }
                    if summary.uncovered > 0 { Label("Reservas sin cobertura: \(Money.format(summary.uncovered)). Revisa tus metas; los gastos se conservan.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    GroupBox("Evolución mensual · resultado") {
                        Chart(months, id: \.self) { month in
                            BarMark(x: .value("Mes", month.label), y: .value("Céntimos", home.summary(month: month).result))
                                .foregroundStyle(.teal)
                                .accessibilityLabel("\(month.label): \(Money.format(home.summary(month: month).result))")
                        }.frame(height: 200).chartYAxis(.hidden)
                        Text("Barras en céntimos; detalle exacto en la lista.").font(.caption)
                        ForEach(months, id: \.self) { month in LabeledContent(month.label, value: Money.format(home.summary(month: month).result)) }
                    }
                    GroupBox("Distribución del gasto del periodo") {
                        VStack {
                            ForEach(HogarCore.Category.allCases, id: \.self) { category in
                                let spent = home.filtered(EntryFilter(month: Month(date), category: category)).filter { $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amount.cents }
                                LabeledContent(category.rawValue, value: Money.format(spent))
                            }
                        }
                    }
                    if home.accounts.isEmpty { Text("Empieza añadiendo una cuenta y su saldo inicial en Cuentas.").foregroundStyle(.secondary) }
                }.padding(24)
            }
        }.navigationTitle("Resumen")
        .toolbar { Button { add = true } label: { Label("Añadir gasto", systemImage: "plus") }.keyboardShortcut("n", modifiers: .command).disabled(store.household?.accounts.isEmpty != false) }
        .sheet(isPresented: $add) { EntryEditor() }
    }
    private var months: [Month] {
        (-5...0).compactMap { Calendar.household.date(byAdding: .month, value: $0, to: date) }.map { Month($0) }
    }
    private func metric(_ title: String, _ cents: Int64, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(Money.format(cents)).font(.title.bold()).monospacedDigit().minimumScaleFactor(0.7)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
        }.padding().frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}
