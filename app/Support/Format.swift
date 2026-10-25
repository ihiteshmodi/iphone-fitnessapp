import FitnessCore
import SwiftUI

/// Shared formatting so every screen shows numbers and dates the same way.
enum Format {
    /// 54 -> "54", 12.5 -> "12.5", 30.375 -> "30.38". Trailing zeros are dropped.
    static func number(_ value: Double, maxDecimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxDecimals
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func fixed(_ value: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", value)
    }

    static func kg(_ value: Double?) -> String { value.map { "\(number($0)) kg" } ?? "–" }

    /// 3037 -> "3,037"
    static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2026-10-18" -> "18 Oct"
    static func shortDate(_ date: ISODate) -> String {
        let parts = date.string.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month) else { return date.string }
        return "\(day) \(months[month - 1])"
    }

    /// "2026-08-31" -> "31 Aug 2026"
    static func longDate(_ date: ISODate) -> String {
        "\(shortDate(date)) \(date.string.prefix(4))"
    }

    /// Accepts "54", "54.5" and "54,5" (decimal comma keyboards).
    static func decimal(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

extension View {
    /// Shows `message` in an alert and clears it when dismissed.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Cannot save", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// Wraps UIActivityViewController so the exported database can go to Files / Google Drive.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
