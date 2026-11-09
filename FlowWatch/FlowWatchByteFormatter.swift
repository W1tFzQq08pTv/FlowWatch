import Foundation

enum FlowWatchByteFormatter {
    static func formatBytes(_ bytes: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = max(bytes, 0)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let stringValue: String
        if value >= 100 {
            stringValue = String(format: "%.0f", value.rounded())
        } else if value >= 10 {
            stringValue = String(format: "%.1f", value)
        } else if unitIndex == 0 {
            stringValue = String(format: "%.0f", value)
        } else {
            stringValue = String(format: "%.1f", value)
        }

        return "\(stringValue) \(units[unitIndex])"
    }

    static func formatMB(_ value: Double) -> String {
        formatBytes(value * 1024 * 1024)
    }

    static func formatCompactMB(_ value: Double) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var scaledValue = max(value, 0) * 1024 * 1024
        var unitIndex = 0

        while scaledValue >= 1024 && unitIndex < units.count - 1 {
            scaledValue /= 1024
            unitIndex += 1
        }

        let stringValue: String
        if unitIndex >= 3 {
            let oneDecimalValue = String(format: "%.1f", scaledValue)
            stringValue = oneDecimalValue.hasSuffix(".0")
                ? String(oneDecimalValue.dropLast(2))
                : oneDecimalValue
        } else {
            stringValue = String(format: "%.0f", scaledValue.rounded())
        }

        return "\(stringValue)\(units[unitIndex])"
    }
}
