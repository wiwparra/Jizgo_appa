import SwiftUI
import PhotosUI
import Vision
import ImageIO
import HogarCore

struct BankNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var message: String?
    @State private var draft: BankNoticeDraft?
    var body: some View {
        NavigationStack {
            Group {
                if let draft { BankNoticeReview(draft: draft, sourceText: text).id(draft.id) }
                else {
                    Form {
                        Section("Texto o captura del aviso") {
                            Text("iPhone no permite leer las notificaciones de otras apps. Selecciona tú una captura o pega el texto del aviso. No incluyas claves ni códigos de seguridad.").font(.callout)
                            TextEditor(text: $text).frame(minHeight: 140).accessibilityLabel("Texto del aviso bancario")
                            PasteButton(payloadType: String.self) { values in text = String(values.joined(separator: "\n").prefix(10001)) }
                            PhotosPicker(selection: $photo, matching: .images) { Label("Seleccionar captura", systemImage: "photo") }.disabled(reading)
                            if reading { ProgressView("Leyendo texto en este dispositivo…") }
                            Button("Preparar movimiento") { prepare() }.disabled(reading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text("La imagen y el aviso no se guardan en el hogar ni se envían a un servidor. Solo se registra el movimiento que confirmes. La captura original seguirá en Fotos hasta que tú la elimines.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let message { Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
                    }.formStyle(.grouped)
                }
            }
            .navigationTitle(draft == nil ? "Aviso bancario" : "Revisar movimiento")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .onChange(of: photo) { _, selected in
                guard let selected else { return }
                reading = true; message = nil
                Task {
                    defer { reading = false; photo = nil }
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self), data.count <= 15 * 1024 * 1024 else {
                            throw FinanceError.invalid("Selecciona una captura de hasta 15 MB.")
                        }
                        text = try await Self.recognize(data)
                    } catch { message = "No se ha podido leer la imagen. Prueba con una captura más nítida o pega el texto." }
                }
            }
        }.frame(minWidth: 300, minHeight: 520)
    }
    private func prepare() {
        do { draft = try BankNoticeParser.parse(text); message = nil }
        catch { message = error.localizedDescription }
    }
    private static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
                  width > 0, height > 0, width <= 16000, height <= 16000, width * height <= 32_000_000 else { throw FinanceError.corrupt }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-ES", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data, options: [:]).perform([request])
            let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !recognized.isEmpty, recognized.count <= 10000 else { throw FinanceError.invalid("No se ha encontrado texto utilizable.") }
            return recognized
        }.value
    }
}

private struct BankNoticeReview: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let draft: BankNoticeDraft
    let sourceText: String
    @State private var amount: String
    @State private var title: String
    @State private var kind: EntryKind?
    @State private var category: HogarCore.Category = .otros
    @State private var account: UUID?
    @State private var destination: UUID?
    @State private var member: UUID?
    @State private var date = Date()
    @State private var tags = ""
    @State private var notes = ""
    @State private var acknowledged = false
    init(draft: BankNoticeDraft, sourceText: String) {
        self.draft = draft
        self.sourceText = sourceText
        _amount = State(initialValue: draft.amount?.input ?? "")
        _title = State(initialValue: draft.suggestedTitle)
        _kind = State(initialValue: draft.kind)
    }
    var body: some View {
        Form {
            InlineSaveError()
            Section("Revisión necesaria") {
                ForEach(draft.warnings, id: \.self) { Text($0).font(.callout) }
                if draft.amount == nil, !draft.candidates.isEmpty {
                    Text("Importes encontrados: " + draft.candidates.map(\.formatted).joined(separator: " · ")).font(.caption)
                }
                DisclosureGroup("Consultar texto original o reconocido") { Text(sourceText).textSelection(.enabled) }
                Text("El reconocimiento puede equivocarse. Contrasta el importe con el aviso original antes de confirmar.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Movimiento") {
                TextField("Importe en euros (12,50)", text: $amount)
                Picker("Tipo", selection: $kind) {
                    Text("Selecciona").tag(nil as EntryKind?)
                    ForEach(EntryKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                TextField("Concepto", text: $title)
                DatePicker("Fecha de la operación", selection: $date, displayedComponents: .date)
                Picker("Cuenta", selection: $account) {
                    Text("Selecciona").tag(nil as UUID?)
                    ForEach(store.household?.accounts ?? []) { Text($0.name).tag(Optional($0.id)) }
                }
                if kind == .transfer {
                    Picker("Cuenta de destino", selection: $destination) {
                        Text("Selecciona").tag(nil as UUID?)
                        ForEach((store.household?.accounts ?? []).filter { $0.id != account }) { Text($0.name).tag(Optional($0.id)) }
                    }
                } else {
                    Picker("Categoría", selection: $category) { ForEach(HogarCore.Category.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                Picker("Atribuido a", selection: $member) { ForEach((store.household?.members ?? []).filter(\.active)) { Text($0.name).tag(Optional($0.id)) } }
                TextField("Etiquetas separadas por comas", text: $tags)
                TextField("Notas opcionales", text: $notes, axis: .vertical)
            }
            if !duplicates.isEmpty {
                Section("Posible duplicado") {
                    ForEach(duplicates) { item in Text("\(item.title) · \(item.amount.formatted)") }
                    Toggle("Lo he revisado: es otro movimiento", isOn: $acknowledged)
                }
            }
            Section {
                Button("Confirmar y registrar") { save() }.disabled(account == nil || member == nil || kind == nil || amount.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty || (!duplicates.isEmpty && !acknowledged))
                Text("Cancelar cierra la propuesta sin cambiar tus finanzas.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .onAppear { member = store.actor }
        .onChange(of: amount) { _, _ in acknowledged = false }
        .onChange(of: account) { _, _ in acknowledged = false }
        .onChange(of: date) { _, _ in acknowledged = false }
        .onChange(of: kind) { _, _ in acknowledged = false }
    }
    private var duplicates: [Entry] {
        guard let home = store.household, let actor = store.actor, let candidate = try? entry(actor: actor) else { return [] }
        return BankNoticeRegistration.possibleDuplicates(of: candidate, in: home)
    }
    private func entry(actor: UUID) throws -> Entry {
        guard let account, let member, let kind else { throw FinanceError.invalid("Selecciona tipo, cuenta y miembro.") }
        return try Entry(id: draft.id, authorID: actor, memberID: member, accountID: account, destinationID: kind == .transfer ? destination : nil, kind: kind, amount: Money(amount), date: date, category: category, title: title, notes: notes, tags: EntryTags.parse(tags))
    }
    private func save() {
        if store.update({ home, actor in
            try BankNoticeRegistration.register(entry(actor: actor), in: &home, actor: actor, confirmed: true, duplicateAcknowledged: acknowledged)
        }) { dismiss() }
    }
}
