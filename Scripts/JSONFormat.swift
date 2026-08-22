import Foundation

/// Serialises line JSON the way the hand-authored files are formatted:
/// 4-space indent, but arrays of scalars stay on one line.
///
/// `JSONSerialization` cannot express that, and it also renders every number
/// as a Double, so the writer walks the tree itself.
enum JSONFormat {

    /// A JSON value, kept in the order the data should be written in.
    indirect enum Value {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case null
        /// Keys are written in the order given; the callers sort them.
        case object([(String, Value)])
        case array([Value])

        var isScalar: Bool {
            switch self {
            case .object, .array: return false
            default: return true
            }
        }
    }

    // MARK: - Writing

    static func pretty(_ value: Value, indent: Int = 4) -> String {
        write(value, indent: indent, level: 0)
    }

    /// One line, no spaces — how catalog.json is published.
    static func compact(_ value: Value) -> String {
        switch value {
        case .object(let pairs):
            return "{" + pairs.map { "\(quote($0.0)):\(compact($0.1))" }.joined(separator: ",") + "}"
        case .array(let items):
            return "[" + items.map(compact).joined(separator: ",") + "]"
        default:
            return scalar(value)
        }
    }

    private static func write(_ value: Value, indent: Int, level: Int) -> String {
        let pad = String(repeating: " ", count: indent * level)
        let inner = String(repeating: " ", count: indent * (level + 1))
        switch value {
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            let body = pairs
                .map { "\(inner)\(quote($0.0)): \(write($0.1, indent: indent, level: level + 1))" }
                .joined(separator: ",\n")
            return "{\n" + body + "\n" + pad + "}"
        case .array(let items):
            if items.isEmpty { return "[]" }
            if items.allSatisfy(\.isScalar) {
                return "[" + items.map(scalar).joined(separator: ", ") + "]"
            }
            let body = items
                .map { inner + write($0, indent: indent, level: level + 1) }
                .joined(separator: ",\n")
            return "[\n" + body + "\n" + pad + "]"
        default:
            return scalar(value)
        }
    }

    private static func scalar(_ value: Value) -> String {
        switch value {
        case .string(let s): return quote(s)
        case .int(let i): return String(i)
        case .double(let d):
            // Whole doubles are written without the ".0" the data never had.
            if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
            return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .object, .array: return ""
        }
    }

    /// Non-ASCII stays as itself, the way the data files are written.
    private static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if c.value < 0x20 {
                    out += String(format: "\\u%04x", c.value)
                } else {
                    out.unicodeScalars.append(c)
                }
            }
        }
        return out + "\""
    }

    // MARK: - Reading

    /// Parses with `JSONSerialization`, then restores integers and sorts keys,
    /// so a file round-trips byte-for-byte.
    static func read(_ data: Data, sortKeys: Bool = true) throws -> Value {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return convert(any, sortKeys: sortKeys)
    }

    static func convert(_ any: Any, sortKeys: Bool = true) -> Value {
        switch any {
        case let dict as [String: Any]:
            let keys = sortKeys ? dict.keys.sorted() : Array(dict.keys)
            return .object(keys.map { ($0, convert(dict[$0]!, sortKeys: sortKeys)) })
        case let array as [Any]:
            return .array(array.map { convert($0, sortKeys: sortKeys) })
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let double = number.doubleValue
            if double == double.rounded(), abs(double) < 1e15,
               String(cString: number.objCType) != "d" {
                return .int(number.intValue)
            }
            return double == double.rounded() && abs(double) < 1e15
                ? .int(number.intValue)
                : .double(double)
        case is NSNull:
            return .null
        default:
            return .null
        }
    }
}
