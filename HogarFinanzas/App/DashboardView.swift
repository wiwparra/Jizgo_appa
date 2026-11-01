import SwiftUI
import Charts
import HogarCore

struct PeriodPicker: View {
    @Binding var date: Date
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
    @State private var bankImport = false
    var body: some View {
        ScrollView {
            if let home = store.household {
                let summary = home.summary(month: Month(date))
                VStack(alignment: .leading, spacing: 16) {
                    if store.demo { Label("Demostración", systemImage: "testtube.2").font(.caption).foregroundStyle(.secondary) }
                    if store.familyEnabled {
                        HStack {
                            Label(syncTitle, systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Actualizar") { Task { await store.synchronizeFamily() } }.font(.caption)
                        }
                    }
                    PeriodPicker(date: $date)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Saldo registrado total").font(.subheadline).foregroundStyle(.secondary)
                        Text(Money.format(summary.balance)).font(.largeTitle.bold()).monospacedDigit().minimumScaleFactor(0.65)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 24) {
                                figure("Reservado", summary.reserved)
                                Spacer(minLength: 0)
                                figure("Sin reservar", summary.unreserved)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Reservado", value: Money.format(summary.reserved))
                                LabeledContent("Sin reservar", value: Money.format(summary.unreserved))
                            }
                        }
                        Text("Sin reservar no descuenta recibos futuros.").font(.caption).foregroundStyle(.secondary)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            figure("Ingresos", summary.income)
                            Spacer(minLength: 0)
                            figure("Gastos", summary.expenses)
                            Spacer(minLength: 0)
                            figure("Resultado", summary.result)
                        }
                        VStack(spacing: 8) {
                            LabeledContent("Ingresos", value: Money.format(summary.income))
                            LabeledContent("Gastos", value: Money.format(summary.expenses))
                            LabeledContent("Resultado", value: Money.format(summary.result))
                        }
                    }.padding(.horizontal, 4)
                    if summary.uncovered > 0 {
                        Label("Reservas sin cobertura: \(Money.format(summary.uncovered))", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    }
                    Button { add = true } label: { Label("Registrar gasto", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6) }.buttonStyle(.borderedProminent).disabled(home.accounts.isEmpty)
                    if home.accounts.isEmpty { Text("Añade tu primera cuenta en Cuentas.").font(.callout).foregroundStyle(.secondary) }
                    DisclosureGroup("Detalle y evolución") { details(home, summary: summary) }
                        .font(.callout).padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }.padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Resumen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button { bankImport = true } label: { Label("Desde aviso bancario", systemImage: "text.viewfinder") }.disabled(store.household?.accounts.isEmpty != false)
            Button { add = true } label: { Label("Añadir gasto", systemImage: "plus") }.keyboardShortcut("n", modifiers: .command).disabled(store.household?.accounts.isEmpty != false)
        }
        .sheet(isPresented: $bankImport) { BankNoticeView() }
        .sheet(isPresented: $add) { EntryEditor() }
    }
    private var syncTitle: String {
        switch store.syncStatus {
        case .localOnly: "Hogar familiar"
        case .pending: "Cambios pendientes"
        case .syncing: "Sincronizando…"
        case .synced: "Sincronizado"
        case .error: "Revisar sincronización en Hogar y copias"
        }
    }
    private func figure(_ title: String, _ cents: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(cents)).font(.headline).monospacedDigit().fixedSize(horizontal: true, vertical: false)
        }.accessibilityElement(children: .combine)
    }
    private func details(_ home: Household, summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("El saldo suma saldos iniciales y todos los movimientos, también los futuros. Las reservas son asignaciones virtuales. Los ingresos, gastos y resultado corresponden al mes seleccionado; no incluyen saldos iniciales ni transferencias.").font(.caption).foregroundStyle(.secondary)
            GroupBox("Saldo por cuenta") {
                VStack { ForEach(home.accounts) { account in LabeledContent(account.name, value: Money.format(home.balance(account: account.id))) } }
            }
            GroupBox("Evolución de seis meses") {
                VStack {
                    Chart(months, id: \.self) { month in
                        BarMark(x: .value("Mes", month.label), y: .value("Céntimos", home.summary(month: month).result)).foregroundStyle(.teal)
                            .accessibilityLabel("\(month.label): \(Money.format(home.summary(month: month).result))")
                    }.frame(height: 170).chartYAxis(.hidden)
                    ForEach(months, id: \.self) { month in LabeledContent(month.label, value: Money.format(home.summary(month: month).result)) }
                }
            }
            GroupBox("Gastos por categoría") {
                VStack {
                    ForEach(HogarCore.Category.allCases, id: \.self) { category in
                        let spent = home.filtered(EntryFilter(month: Month(date), category: category)).filter { $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amount.cents }
                        LabeledContent(category.rawValue, value: Money.format(spent))
                    }
                }
            }
        }.padding(.top, 12)
    }
    private var months: [Month] { (-5...0).compactMap { Calendar.household.date(byAdding: .month, value: $0, to: date) }.map { Month($0) } }
}
