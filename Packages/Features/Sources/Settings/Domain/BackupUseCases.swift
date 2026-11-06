import Domain
import Foundation

/// The backup file written before the portable format (`BackupSnapshot`, `schemaVersion`): it has
/// `version: 1`, amounts as JSON numbers and no audit dates. Read only, so files people already
/// keep still restore.
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

    /// Its records as they were on `createdAt`. A default category missing from the file was
    /// deleted on purpose, so it becomes a tombstone instead of being seeded back.
    var contents: BackupContents {
        let stamp = RecordMetadata(createdAt: createdAt, updatedAt: createdAt)
        let listed = Set(categories.map(\.id))
        let deletedDefaults = TransactionCategory.defaults
            .filter { !listed.contains($0.id) && !$0.isFallback }
            .map { Stamped($0, RecordMetadata(createdAt: createdAt, updatedAt: createdAt, deletedAt: createdAt)) }
        return BackupContents(
            settings: Stamped(settings, stamp),
            accounts: accounts.map { Stamped($0, stamp) },
            cards: cards.map { Stamped($0, stamp) },
            categories: categories.map { Stamped($0, stamp) } + deletedDefaults,
            transactions: transactions.map { Stamped($0, stamp) },
        )
    }
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

/// "Back up now": the whole store as a portable `BackupSnapshot` file (`currentSchemaVersion`), which
/// the person keeps wherever they choose (iCloud Drive, Files) and the web app can open too.
public protocol CreateBackupUseCase: Sendable {
    /// The backup file's contents.
    func execute() async throws(DomainError) -> Data
}

public struct DefaultCreateBackupUseCase: CreateBackupUseCase {
    private let store: any BackupStore
    private let now: @Sendable () -> Date

    public init(store: any BackupStore, now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.now = now
    }

    public func execute() async throws(DomainError) -> Data {
        guard let snapshot = try await BackupSnapshot(contents: store.exportContents(), exportedAt: now()) else {
            throw .persistence("Nothing to back up yet")
        }
        return try snapshot.encoded()
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
    private let store: any BackupStore

    public init(store: any BackupStore) {
        self.store = store
    }

    public func execute(_ data: Data) async throws(DomainError) -> RestoreSummary {
        // Decoded and validated in full first, so a wrong or damaged file never erases anything.
        var (contents, backupDate) = try Self.read(data)
        guard var settings = contents.settings?.value, let metadata = contents.settings?.metadata else {
            throw .corruptedData("Backup without settings")
        }
        settings.hasCompletedOnboarding = true
        contents.settings = Stamped(settings, metadata)
        try await store.replaceAll(with: contents)
        return RestoreSummary(
            accounts: contents.accounts.count { !$0.metadata.isDeleted },
            transactions: contents.transactions.count { !$0.metadata.isDeleted },
            backupDate: backupDate,
        )
    }

    /// The portable format names its `schemaVersion`; the earlier one only had `version`.
    static func read(_ data: Data) throws(DomainError) -> (BackupContents, Date) {
        struct Header: Decodable {
            let schemaVersion: Int?
            let version: Int?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw .corruptedData("Not a Keepwell backup")
        }
        if header.schemaVersion != nil {
            let snapshot = try BackupSnapshot.decode(data)
            return try (snapshot.contents(), snapshot.exportedAt)
        }
        guard let version = header.version else { throw .corruptedData("Not a Keepwell backup") }
        guard version <= BackupDocument.currentVersion else {
            throw .corruptedData("Backup version \(version) is newer than this app")
        }
        do {
            let document = try BackupDocument.decoder.decode(BackupDocument.self, from: data)
            return (document.contents, document.createdAt)
        } catch {
            throw .corruptedData("Not a Keepwell backup: \(error)")
        }
    }
}
