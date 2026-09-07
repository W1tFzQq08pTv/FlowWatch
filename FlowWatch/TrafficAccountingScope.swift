import Foundation
import SystemConfiguration

enum TrafficAccountingScope: String, CaseIterable, Sendable {
    case external
    case local
    case other
    case legacy

    static func classify(interface: String, externalInterfaces: Set<String>) -> Self {
        if interface.hasPrefix("lo") { return .local }
        return externalInterfaces.contains(interface) ? .external : .other
    }

    // 使用系统登记的硬件接口，不将 VPN、网桥或虚拟机接口视为外部接口。
    static func externalInterfaceNames() -> Set<String> {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let hardwareTypes = [kSCNetworkInterfaceTypeEthernet, kSCNetworkInterfaceTypeIEEE80211, kSCNetworkInterfaceTypeWWAN]
        return Set(interfaces.compactMap { interface in
            guard let type = SCNetworkInterfaceGetInterfaceType(interface),
                  hardwareTypes.contains(where: { $0 == type }),
                  let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            return name
        })
    }
}
