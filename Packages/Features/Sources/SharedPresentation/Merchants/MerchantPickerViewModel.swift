import Domain
import Foundation
import Observation

/// "Business" or "Via": a search over the person's merchants, the app's brand table and, when
/// neither has what is typed, Brandfetch's brand search (debounced). A found brand or a typed name is
/// only created as a merchant when the movement is saved, so picking hands over a `MerchantChoice`.
@MainActor
@Observable
public final class MerchantPickerViewModel: Identifiable {
    public let role: MerchantRole
    public let merchants: [Merchant]
    /// The business itself, never offered as its own platform.
    public let excludedID: UUID?
    /// What the field holds when the picker opens.
    public let current: MerchantChoice?
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    /// Brandfetch's answer for `remote.query`, kept only while the query is still that text.
    public private(set) var remote: (query: String, results: [BrandSearchResult])?
    public private(set) var isSearching = false

    private let search: (any BrandSearching)?
    private let debounce: Duration
    private let onPick: (MerchantChoice?) -> Void
    private var task: Task<Void, Never>?

    /// Without `search` (the logos are off) only the person's merchants and the brand table show.
    public init(
        role: MerchantRole,
        merchants: [Merchant],
        current: MerchantChoice?,
        excluding excludedID: UUID? = nil,
        search: (any BrandSearching)?,
        debounce: Duration = BrandSearch.debounce,
        onPick: @escaping (MerchantChoice?) -> Void,
    ) {
        self.role = role
        self.merchants = merchants
        self.current = current
        self.excludedID = excludedID
        self.search = search
        self.debounce = debounce
        self.onPick = onPick
    }

    private var local: [MerchantOption] {
        MerchantOption.options(query: query, merchants: merchants, role: role, excluding: excludedID)
    }

    /// Whether Brandfetch is asked for the current query.
    public var wantsRemote: Bool {
        search != nil && MerchantOption.needsBrandSearch(query, local: local)
    }

    public var options: [MerchantOption] {
        guard wantsRemote, let remote, remote.query == query else { return local }
        return MerchantOption.options(query: query, merchants: merchants, remote: remote.results, role: role, excluding: excludedID)
    }

    public var currentName: String? {
        current?.name(in: merchants)
    }

    public func pick(_ option: MerchantOption) {
        onPick(option.choice)
    }

    /// "Remove": the movement names no business (or platform).
    public func clear() {
        onPick(nil)
    }

    /// Finishes a pending request; tests await it instead of the debounce.
    public func waitForSearch() async {
        await task?.value
    }

    private func scheduleSearch() {
        task?.cancel()
        isSearching = false
        guard wantsRemote, let search else { return }
        let query = query
        isSearching = true
        let debounce = debounce
        task = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let results = await search.search(query)
            guard !Task.isCancelled, let self, self.query == query else { return }
            remote = (query, results)
            isSearching = false
        }
    }
}
