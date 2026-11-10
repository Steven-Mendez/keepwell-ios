import Foundation

/// The language the sample's own words are written in. Names and descriptions are data the person
/// typed, not interface text, so they never go through a string catalog: a Spanish sample is simply
/// a sample someone wrote in Spanish (App Store screenshots, demos).
public enum SampleLanguage: Sendable {
    case english
    case spanish

    /// Spanish for any Spanish locale, English otherwise.
    public init(languageCode: String?) {
        self = languageCode?.hasPrefix("es") == true ? .spanish : .english
    }
}

extension SampleData {
    static func text(_ english: String, _ language: SampleLanguage) -> String {
        guard language == .spanish else { return english }
        return spanish[english] ?? english
    }

    private static let spanish: [String: String] = [
        // Accounts
        "Savings": "Ahorros",
        "Payroll": "Nómina",
        "Wallet": "Billetera",
        "Bank One": "Banco Uno",
        "Bank Two": "Banco Dos",
        // Movements
        "Monthly groceries": "Súper del mes",
        "Family support": "Apoyo familiar",
        "Electricity (estimate)": "Luz (estimado)",
        "Phone": "Teléfono",
        "Design software": "Software de diseño",
        "Home internet": "Internet de la casa",
        "Salary": "Salario",
        "Card replacement": "Reposición de tarjeta",
        "Lunch": "Almuerzo",
        "Bus": "Bus",
        "Movies": "Cine",
        "Cardless withdrawal": "Retiro sin tarjeta",
        "Groceries": "Súper",
        "Streaming": "Streaming",
        "Music": "Música",
        "Interest": "Intereses",
        "Dinner": "Cena",
        "Online course": "Curso en línea",
        // Plans, goals, loans and debts
        "Rent": "Alquiler",
        "Cash for the week": "Efectivo de la semana",
        "Trip": "Viaje",
        "Emergency fund": "Fondo de emergencia",
        "New phone": "Teléfono nuevo",
        "Motorbike": "Moto",
        "Concert": "Concierto",
    ]
}
