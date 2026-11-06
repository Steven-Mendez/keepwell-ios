import Domain
import Foundation

/// A complete copy of the person's data in one file: "Back up now" writes it wherever they choose
/// (iCloud Drive, Files) and "Restore" brings it back. It complements the automatic iCloud sync
/// with a copy the person holds and can move to another phone or keep before a big change.
public struct BackupDocument: Codable, Sendable, Equatable {
    /// Raised when the format changes, so an older app can refuse a file it doesn't understand.
    public static let currentVersion = 1

    public let version: Int
    public let createdAt: Date
    public let settings: Settings
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]
    public let transactions: [Transaction]

    public init(
        createdAt: Date,
        settings: Settings,
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
        transactions: [Transaction],
    ) {
        version = Self.currentVersion
        self.createdAt = createdAt
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.transactions = transactions
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case createdAt
        case settings
        case accounts
        case cards
        case categories
        case transactions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        settings = try container.decode(Settings.self, forKey: .settings)
        accounts = try container.decode([Account].self, forKey: .accounts)
        cards = try container.decode([StoredCard].self, forKey: .cards).compactMap(\.card)
        categories = try container.decode([TransactionCategory].self, forKey: .categories)
        transactions = try container.decode([Transaction].self, forKey: .transactions)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// A card as an older backup may hold it. Files written while cards could have additionals list
/// them too; those are dropped, since their purchases already belong to their credit account.
private struct StoredCard: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
    }

    let card: Card?

    init(from decoder: any Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .kind)
        card = kind == "creditAdditional" ? nil : try Card(from: decoder)
    }
}

public protocol CreateBackupUseCase: Sendable {
    /// The backup file's contents.
    func execute() async throws(DomainError) -> Data
}

public struct DefaultCreateBackupUseCase: CreateBackupUseCase {
    private let settings: any SettingsRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let transactions: any TransactionRepository
    private let now: @Sendable () -> Date

    public init(
        settings: any SettingsRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        transactions: any TransactionRepository,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.transactions = transactions
        self.now = now
    }

    public func execute() async throws(DomainError) -> Data {
        guard let current = try await settings.load() else { throw .persistence("Nothing to back up yet") }
        let records = try await LedgerRecords.load(accounts: accounts, cards: cards, transactions: transactions, categories: categories)
        let document = BackupDocument(
            createdAt: now(),
            settings: current,
            accounts: records.accounts,
            cards: records.cards,
            categories: records.categories,
            transactions: records.transactions,
        )
        do {
            return try BackupDocument.encoder.encode(document)
        } catch {
            throw .persistence("Backup encoding: \(error)")
        }
    }
}

/// What a restore brought back, for the message after it.
public struct RestoreSummary: Hashable, Sendable {
    public let accounts: Int
    public let transactions: Int
    public let backupDate: Date
}

public protocol RestoreBackupUseCase: Sendable {
    /// Checks the file before touching anything, then replaces all data with it.
    func execute(_ data: Data) async throws(DomainError) -> RestoreSummary
}

public struct DefaultRestoreBackupUseCase: RestoreBackupUseCase {
    private let eraser: any DataEraser
    private let settings: any SettingsRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let transactions: any TransactionRepository

    public init(
        eraser: any DataEraser,
        settings: any SettingsRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        transactions: any TransactionRepository,
    ) {
        self.eraser = eraser
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.transactions = transactions
    }

    public func execute(_ data: Data) async throws(DomainError) -> RestoreSummary {
        // Decoded and validated in full first, so a wrong or damaged file never erases anything.
        let document: BackupDocument
        do {
            document = try BackupDocument.decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw .corruptedData("Not a Keepwell backup: \(error)")
        }
        guard document.version <= BackupDocument.currentVersion else {
            throw .corruptedData("Backup version \(document.version) is newer than this app")
        }
        try await eraser.eraseAll()
        var restoredSettings = document.settings
        restoredSettings.hasCompletedOnboarding = true
        try await settings.save(restoredSettings)
        for category in document.categories {
            try await categories.save(category)
        }
        // A default missing from the file was deleted on purpose; without this it would be seeded back.
        let restoredIDs = Set(document.categories.map(\.id))
        for category in TransactionCategory.defaults where !restoredIDs.contains(category.id) && !category.isFallback {
            try await categories.deleteCategory(id: category.id)
        }
        for account in document.accounts {
            try await accounts.save(account)
        }
        for card in document.cards {
            try await cards.save(card)
        }
        for transaction in document.transactions {
            try await transactions.save(transaction)
        }
        return RestoreSummary(accounts: document.accounts.count, transactions: document.transactions.count, backupDate: document.createdAt)
    }
}
