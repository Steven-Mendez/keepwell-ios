import Foundation

/// JSON passed through untouched (rows go to SwiftData as the server sent them).
public struct RawJSON: Codable, Sendable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    var object: [String: Any]? { try? JSONSerialization.jsonObject(with: data) as? [String: Any] }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(AnyCodable.self)
        data = try JSONSerialization.data(withJSONObject: value.value, options: [.fragmentsAllowed])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(AnyCodable(JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])))
    }
}

/// Just enough to carry arbitrary JSON through Codable.
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([Self].self) {
            value = array.map(\.value)
        } else {
            value = try container.decode([String: Self].self).mapValues(\.value)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): try container.encode(number.boolValue)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map(Self.init))
        case let object as [String: Any]: try container.encode(object.mapValues(Self.init))
        default: try container.encodeNil()
        }
    }
}
