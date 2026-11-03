import Domain
import Foundation

extension DomainError {
    /// User-facing text lives in Presentation; the associated values in Domain are for logs only.
    var userMessage: String {
        switch self {
        case .invalidAmount: "El monto debe ser mayor que cero."
        case let .invalidCurrency(code): "“\(code)” no es una moneda válida."
        case .categoryKindMismatch: "La categoría no corresponde al tipo de movimiento."
        case .unsupportedTransactionKind: "Este tipo de movimiento aún no está disponible."
        case .invalidPeriod: "El periodo seleccionado no es válido."
        case .notFound: "El movimiento ya no existe."
        case .corruptedData, .persistence: "No pudimos acceder a tus datos. Inténtalo de nuevo."
        }
    }
}
