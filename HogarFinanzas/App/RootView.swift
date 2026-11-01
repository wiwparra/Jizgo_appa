import SwiftUI
import HogarCore

private enum SectionItem: String, CaseIterable, Identifiable {
    case summary = "Resumen", entries = "Movimientos", accounts = "Cuentas", plans = "Planificación", settings = "Hogar y copias"
    var id: String { rawValue }
    var tabTitle: String { switch self { case .plans: "Planes"; case .settings: "Hogar"; default: rawValue } }
    var symbol: String {
        switch self { case .summary: "chart.bar.xaxis"; case .entries: "arrow.up.arrow.down"; case .accounts: "wallet.pass"; case .plans: "target"; case .settings: "house" }
    }
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: SectionItem? = .summary
    var body: some View {
        Group {
            if store.readFailed {
                NavigationStack {
                    VStack(spacing: 20) {
                        ContentUnavailableView("No se pudieron leer tus datos", systemImage: "externaldrive.badge.exclamationmark", description: Text("El archivo original se conserva. Reintenta o restaura una copia válida desde Hogar y copias."))
                        Button("Reintentar lectura") { store.load() }
                        SettingsView()
                    }.padding()
                }
            } else if store.household == nil { WelcomeView() }
            else {
                #if os(macOS)
                NavigationSplitView {
                    List(SectionItem.allCases, selection: $selection) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }.navigationTitle(store.household?.name ?? "Hogar Finanzas")
                } detail: {
                    NavigationStack { content(selection ?? .summary) }
                }
                #else
                TabView {
                    ForEach(SectionItem.allCases) { section in
                        NavigationStack { content(section) }.tabItem { Label(section.tabTitle, systemImage: section.symbol) }
                    }
                }
                #endif
            }
        }
        .alert("No se ha podido completar", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Entendido") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    @ViewBuilder private func content(_ section: SectionItem) -> some View {
        switch section {
        case .summary: DashboardView()
        case .entries: EntriesView()
        case .accounts: AccountsView()
        case .plans: PlansView()
        case .settings: SettingsView()
        }
    }
}
struct WelcomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var name = "Mi hogar"
    @State private var owner = ""
    @State private var family = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Hogar Finanzas", systemImage: "house.fill").font(.largeTitle.bold())
                    Text("Tus cuentas, tus planes y tus próximos pasos.").foregroundStyle(.secondary)
                }
                Section("Crear hogar local") {
                    TextField("Nombre del hogar", text: $name)
                    TextField("Tu nombre", text: $owner)
                    Button("Crear hogar") { store.create(name: name, owner: owner) }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || owner.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section {
                    Text("Puedes empezar con datos locales o conectar un hogar compartido con cuentas personales.")
                    Button("Acceder a un hogar familiar") { family = true }
                    Button("Explorar con datos de demostración") { store.setDemo(true) }
                }
            }.formStyle(.grouped).navigationTitle("Bienvenido")
            .sheet(isPresented: $family) { NavigationStack { FamilySettingsView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { family = false } } } } }
        }
    }
}
