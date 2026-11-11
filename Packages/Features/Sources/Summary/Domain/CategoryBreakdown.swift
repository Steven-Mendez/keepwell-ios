import Domain
import Foundation

/// A month's categories ready for a ring chart: the largest ones by name and the long tail folded
/// into one slice, because a ring with a dozen slivers can't be read.
public struct CategoryBreakdown: Hashable, Sendable {
    public enum Slice: Hashable, Sendable {
        case category(String)
        /// The categories past the named ones, with how many there are.
        case others(count: Int)
    }

    public struct Entry: Hashable, Sendable {
        public let slice: Slice
        public let amount: Decimal
        /// Share of `total` (0…1).
        public let share: Decimal
    }

    /// Named slices before the rest is grouped.
    public static let maxNamedSlices = 5

    public let total: Decimal
    /// Largest first; the grouped slice, when there is one, comes last.
    public let entries: [Entry]

    /// `totals` must already be ranked largest first, as `MonthlySummary` returns them.
    public init(totals: [MonthlySummary.CategoryTotal], maxNamedSlices: Int = Self.maxNamedSlices) {
        self.init(ranked: totals.map { ($0.categoryID, $0.amount) }, maxNamedSlices: maxNamedSlices)
    }

    /// A range's categories: only what was spent (or received) in the period, largest first, as the
    /// web's `ranked` does before it builds the ring.
    public init(changes: [CategoryChange], maxNamedSlices: Int = Self.maxNamedSlices) {
        self.init(ranked: changes.filter { $0.amount > 0 }.map { ($0.categoryID, $0.amount) }, maxNamedSlices: maxNamedSlices)
    }

    private init(ranked: [(id: String, amount: Decimal)], maxNamedSlices: Int) {
        let total = ranked.reduce(Decimal(0)) { $0 + $1.amount }
        // Folding a single category into "others" would only hide its name.
        let named = ranked.count > maxNamedSlices + 1 ? Array(ranked.prefix(maxNamedSlices)) : ranked
        var entries = named.map { Entry(slice: .category($0.id), amount: $0.amount, share: total > 0 ? $0.amount / total : 0) }
        let rest = ranked.dropFirst(named.count)
        if !rest.isEmpty {
            let amount = rest.reduce(Decimal(0)) { $0 + $1.amount }
            entries.append(Entry(slice: .others(count: rest.count), amount: amount, share: total > 0 ? amount / total : 0))
        }
        self.total = total
        self.entries = entries
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }
}
