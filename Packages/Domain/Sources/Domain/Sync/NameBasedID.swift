import Foundation

/// RFC 9562 name-based UUIDs (version 5, SHA-1), identical to keepwell-web's `uuidV5`. The same
/// name gives the same id on every device and on the server, so an occurrence of a recurring rule
/// or an installment of a loan produced twice is one record, and sync merges it on its own. The
/// shared fixture `ids.json` holds the vectors every suite checks.
public enum NameBasedID {
    /// `uuidV5("keepwell", URL namespace)`.
    public static let keepwellNamespace = UUID(uuidString: "b21aa395-c3f3-574c-b9a1-bf3e47f340c5") ?? UUID()

    public static func uuidV5(_ name: String, namespace: UUID = keepwellNamespace) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(name.utf8))
        var bytes = Array(SHA1.digest(Array(data)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        ))
    }

    /// The movement for the `index`-th occurrence of a rule. The schedule is part of the name, so
    /// editing it never makes a new occurrence collide with an old movement.
    public static func occurrence(ruleID: UUID, startDate: Date, frequency: RecurringFrequency, interval: Int, index: Int) -> UUID {
        uuidV5("occurrence|\(ruleID.uuidString.lowercased())|\(isoMilliseconds(startDate))|\(frequency.rawValue)|\(interval)|\(index)")
    }

    /// One installment of a loan: paying number 3 on two devices records one payment.
    public static func loanPayment(loanID: UUID, number: Int) -> UUID {
        uuidV5("loan-payment|\(loanID.uuidString.lowercased())|\(number)")
    }

    /// A repayment that predates repayment ids, by what it was.
    public static func legacyRepayment(debtID: UUID, index: Int, date: Date, amount: Decimal) -> UUID {
        uuidV5("debt-repayment|\(debtID.uuidString.lowercased())|\(index)|\(isoMilliseconds(date))|\(amount)")
    }

    /// `Date.toISOString()` in JavaScript: UTC, always three fractional digits.
    public static func isoMilliseconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000))
    }
}

// The round variables keep FIPS 180-4's names (a…e, f, k) so the code can be checked against it.
// swiftlint:disable identifier_name

/// Plain SHA-1 in Swift, as keepwell-web has it in TypeScript: Domain imports only Foundation. Only
/// for name-based ids, never for security.
enum SHA1 {
    static func digest(_ message: [UInt8]) -> [UInt8] {
        var bytes = message
        let bitLength = UInt64(message.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        var hash: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        var words = [UInt32](repeating: 0, count: 80)
        for block in stride(from: 0, to: bytes.count, by: 64) {
            for index in 0 ..< 16 {
                let offset = block + index * 4
                words[index] = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 |
                    UInt32(bytes[offset + 3])
            }
            for index in 16 ..< 80 {
                let value = words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16]
                words[index] = value << 1 | value >> 31
            }
            var (a, b, c, d, e) = (hash[0], hash[1], hash[2], hash[3], hash[4])
            for index in 0 ..< 80 {
                let (f, k): (UInt32, UInt32) = switch index {
                case 0 ..< 20: ((b & c) | (~b & d), 0x5A82_7999)
                case 20 ..< 40: (b ^ c ^ d, 0x6ED9_EBA1)
                case 40 ..< 60: ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
                default: (b ^ c ^ d, 0xCA62_C1D6)
                }
                let temp = (a << 5 | a >> 27) &+ f &+ e &+ k &+ words[index]
                e = d
                d = c
                c = b << 30 | b >> 2
                b = a
                a = temp
            }
            hash[0] &+= a
            hash[1] &+= b
            hash[2] &+= c
            hash[3] &+= d
            hash[4] &+= e
        }
        return hash.flatMap { word in (0 ..< 4).map { UInt8(truncatingIfNeeded: word >> UInt32(24 - $0 * 8)) } }
    }
}

// swiftlint:enable identifier_name
