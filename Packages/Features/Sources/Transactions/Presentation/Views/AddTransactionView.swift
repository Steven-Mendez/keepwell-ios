import DesignSystem
import Domain
import SwiftUI
import TransactionsDomain

public struct AddTransactionView: View {
    @State private var viewModel: AddTransactionViewModel
    private let onSaved: () -> Void

    public init(viewModel: AddTransactionViewModel, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSaved = onSaved
    }

    public var body: some View {
        Form {
            Section {
                Picker("Tipo", selection: $viewModel.kind) {
                    ForEach(viewModel.availableKinds, id: \.self) { kind in
                        Text(kind == .income ? "Ingreso" : "Gasto").tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    // `Decimal.FormatStyle` keeps the typed value exact; no `Double` round-trip.
                    TextField("0.00", value: $viewModel.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .kwTextStyle(.amountSm)
                        .accessibilityIdentifier("addTransaction.amount")
                    Picker("Moneda", selection: $viewModel.currency) {
                        ForEach(viewModel.availableCurrencies, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                }
            }

            Section {
                Picker("Categoría", selection: $viewModel.category) {
                    ForEach(viewModel.availableCategories) { Text($0.name).tag($0) }
                }
                DatePicker("Fecha", selection: $viewModel.date, displayedComponents: .date)
                Toggle("Previsto", isOn: $viewModel.isPlanned)
                TextField("Nota", text: $viewModel.note, axis: .vertical)
            } footer: {
                if viewModel.isPlanned {
                    Text("Los movimientos previstos no cuentan en el resumen hasta confirmarlos.")
                }
            }
        }
        .navigationTitle("Nuevo movimiento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    Task {
                        if await viewModel.save() {
                            onSaved()
                        }
                    }
                }
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("addTransaction.save")
            }
        }
        .alert(
            "No se pudo guardar",
            isPresented: Binding(get: { viewModel.error != nil }, set: {
                if !$0 {
                    viewModel.error = nil
                }
            }),
            presenting: viewModel.error,
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.userMessage)
        }
    }
}

#if DEBUG
import TransactionsData

#Preview("Add transaction") {
    NavigationStack {
        AddTransactionView(
            viewModel: AddTransactionViewModel(
                addTransaction: DefaultAddTransactionUseCase(repository: InMemoryTransactionRepository()),
                currencies: ["USD", "NIO"],
            ),
            onSaved: {},
        )
    }
    .preferredColorScheme(.dark)
    .onAppear { KWFonts.register() }
}
#endif
