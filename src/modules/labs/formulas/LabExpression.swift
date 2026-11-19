import Foundation

/// Evaluates the catalogue's formula text: numbers, {marker-id}, + - * /, parentheses and the comparisons > < >= <= (1 or 0).
/// Ids sit in braces because marker ids contain hyphens. Any missing input, malformed text or division by zero gives nil.
public enum LabExpression {
    public static func evaluate(_ text: String, values: [String: Double]) -> Double? {
        var parser = Parser(tokens: tokenize(text), values: values)
        guard let result = parser.comparison(), parser.atEnd, result.isFinite else { return nil }
        return result
    }

    fileprivate enum Token: Equatable {
        case number(Double), id(String), symbol(String), invalid
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            let next = text.index(after: index)
            if char.isWhitespace {
                index = next
            } else if char == "{" {
                guard let close = text[index...].firstIndex(of: "}") else { return [.invalid] }
                tokens.append(.id(String(text[next..<close])))
                index = text.index(after: close)
            } else if char.isNumber || char == "." {
                let end = text[index...].firstIndex { !($0.isNumber || $0 == ".") } ?? text.endIndex
                guard let number = Double(text[index..<end]) else { return [.invalid] }
                tokens.append(.number(number))
                index = end
            } else if char == ">" || char == "<", next < text.endIndex, text[next] == "=" {
                tokens.append(.symbol("\(char)="))
                index = text.index(after: next)
            } else if "+-*/()<>".contains(char) {
                tokens.append(.symbol(String(char)))
                index = next
            } else {
                return [.invalid]
            }
        }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        let values: [String: Double]
        var position = 0

        init(tokens: [Token], values: [String: Double]) {
            self.tokens = tokens
            self.values = values
        }

        var atEnd: Bool { position == tokens.count }

        private mutating func take(_ symbols: Set<String>) -> String? {
            guard position < tokens.count, case .symbol(let symbol) = tokens[position], symbols.contains(symbol) else { return nil }
            position += 1
            return symbol
        }

        mutating func comparison() -> Double? {
            guard let left = sum() else { return nil }
            guard let op = take([">", "<", ">=", "<="]) else { return left }
            guard let right = sum() else { return nil }
            switch op {
            case ">": return left > right ? 1 : 0
            case "<": return left < right ? 1 : 0
            case ">=": return left >= right ? 1 : 0
            default: return left <= right ? 1 : 0
            }
        }

        mutating func sum() -> Double? {
            guard var total = product() else { return nil }
            while let op = take(["+", "-"]) {
                guard let next = product() else { return nil }
                total = op == "+" ? total + next : total - next
            }
            return total
        }

        mutating func product() -> Double? {
            guard var total = unary() else { return nil }
            while let op = take(["*", "/"]) {
                guard let next = unary(), op == "*" || next != 0 else { return nil }
                total = op == "*" ? total * next : total / next
            }
            return total
        }

        mutating func unary() -> Double? {
            if take(["-"]) != nil { return unary().map { -$0 } }
            return primary()
        }

        mutating func primary() -> Double? {
            guard position < tokens.count else { return nil }
            let token = tokens[position]
            position += 1
            switch token {
            case .number(let number): return number
            case .id(let id): return values[id]
            case .symbol("("):
                guard let inner = sum(), take([")"]) != nil else { return nil }
                return inner
            default: return nil
            }
        }
    }
}
