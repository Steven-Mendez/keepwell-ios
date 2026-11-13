import DesignSystem
import SwiftUI

/// The lines under a month's totals that say what they leave out ("Not including 3 movements in
/// USD"): movements whose stored rate can't reach today's main currency. Each screen localizes its
/// lines; this keeps them looking the same wherever a month total appears.
public struct ExcludedMovementsNote: View {
    private let lines: [String]

    public init(_ lines: [String]) {
        self.lines = lines
    }

    public var body: some View {
        ForEach(lines, id: \.self) { line in
            Text(line)
                .font(KWTextStyle.caption.font.weight(.regular))
                .foregroundStyle(KWColor.Text.secondary)
                .monospacedDigit()
        }
    }
}
