import NetworkExtension
import Foundation

// MARK: - Shared lag state via UserDefaults App Group
private let kAppGroup = "group.com.fakelag.app"
private let kLagEnabledKey = "lagEnabled"
private let kLagDelayKey = "lagDelayMs"

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var lagEnabled: Bool {
        UserDefaults(suiteName: kAppGroup)?.bool(forKey: kLagEnabledKey) ?? false
    }

    private var lagDelayMs: Int {
        UserDefaults(suiteName: kAppGroup)?.integer(forKey: kLagDelayKey).nonZero ?? 800
    }

    // MARK: - Tunnel lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Configure a fake virtual interface — all device traffic passes through here
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")

        // IPv4 route — capture ALL traffic through the tunnel
        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // DNS — use Google DNS (so DNS resolution itself still works)
        let dns = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.dnsSettings = dns

        // MTU
        settings.mtu = 1500

        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            completionHandler(nil)
            self.startReadingPackets()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: - Packet forwarding loop

    private func startReadingPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            self.handlePackets(packets: packets, protocols: protocols)
            // Continue reading indefinitely
            self.startReadingPackets()
        }
    }

    private func handlePackets(packets: [Data], protocols: [NSNumber]) {
        guard !packets.isEmpty else { return }

        if lagEnabled {
            // Inject artificial delay — simulates network lag for ALL app traffic
            let delayNs = UInt64(lagDelayMs) * 1_000_000
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(delayNs))) { [weak self] in
                self?.packetFlow.writePackets(packets, withProtocols: protocols)
            }
        } else {
            // No lag — forward immediately
            packetFlow.writePackets(packets, withProtocols: protocols)
        }
    }
}

// MARK: - Helpers
private extension Int {
    var nonZero: Int { self == 0 ? 800 : self }
}
