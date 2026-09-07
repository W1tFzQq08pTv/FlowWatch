import Darwin
import Foundation

struct NettopTrafficAccounting {
    struct Entry {
        let pid: pid_t
        let processName: String
        let connection: String
        let interface: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    struct Delta {
        let entry: Entry
        let scope: TrafficAccountingScope
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private struct Connection: Hashable {
        let pid: pid_t
        let name: String
    }

    private struct Key: Hashable {
        let connection: Connection
        let interface: String
    }

    private var previous: [Key: Entry] = [:]
    private var hasBaseline = false

    mutating func sample(_ entries: [Entry], externalInterfaces: Set<String>) -> [Delta] {
        let previousConnections = Set(previous.keys.map(\.connection))
        var current: [Key: Entry] = [:]
        var deltas: [Delta] = []
        for entry in entries {
            let connection = Connection(pid: entry.pid, name: entry.connection)
            let key = Key(connection: connection, interface: entry.interface)
            guard current[key] == nil else { continue }
            current[key] = entry
            let baseline = previous[key]
            // 首帧只建立基线；后续新连接从零计数。路由变化只重建接口基线。
            let canCount = baseline != nil || (hasBaseline && !previousConnections.contains(connection))
            let bytesIn = canCount && entry.bytesIn >= (baseline?.bytesIn ?? 0)
                ? entry.bytesIn - (baseline?.bytesIn ?? 0) : 0
            let bytesOut = canCount && entry.bytesOut >= (baseline?.bytesOut ?? 0)
                ? entry.bytesOut - (baseline?.bytesOut ?? 0) : 0
            deltas.append(Delta(
                entry: entry,
                scope: TrafficAccountingScope.classify(interface: entry.interface, externalInterfaces: externalInterfaces),
                bytesIn: bytesIn, bytesOut: bytesOut
            ))
        }
        previous = current
        hasBaseline = true
        return deltas
    }

    static func parse(_ output: String) -> [Entry]? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let header = lines.first?.components(separatedBy: ","),
              let interfaceIndex = header.firstIndex(of: "interface"),
              let inIndex = header.firstIndex(of: "bytes_in"),
              let outIndex = header.firstIndex(of: "bytes_out") else { return nil }
        var process: (name: String, pid: pid_t)?
        var entries: [Entry] = []
        for line in lines.dropFirst() {
            let columns = line.components(separatedBy: ",")
            guard columns.count > max(interfaceIndex, max(inIndex, outIndex)) else { continue }
            let field = columns[0].trimmingCharacters(in: .whitespaces)
            if field.hasPrefix("tcp4 ") || field.hasPrefix("tcp6 ") || field.hasPrefix("udp4 ") || field.hasPrefix("udp6 ") {
                guard let process else { continue }
                entries.append(Entry(
                    pid: process.pid, processName: process.name, connection: field,
                    interface: columns[interfaceIndex].trimmingCharacters(in: .whitespaces),
                    bytesIn: UInt64(columns[inIndex]) ?? 0, bytesOut: UInt64(columns[outIndex]) ?? 0
                ))
            } else {
                process = parseProcessField(field)
            }
        }
        return entries
    }

    private static func parseProcessField(_ field: String) -> (name: String, pid: pid_t)? {
        guard let lastDotIndex = field.lastIndex(of: ".") else { return nil }
        let name = String(field[field.startIndex..<lastDotIndex])
        let pidString = String(field[field.index(after: lastDotIndex)...])
        guard let pid = pid_t(pidString) else { return nil }
        return (name: name, pid: pid)
    }
}
