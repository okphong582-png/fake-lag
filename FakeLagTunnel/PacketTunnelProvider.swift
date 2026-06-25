import NetworkExtension
import Foundation

// MARK: - Shared lag state via UserDefaults App Group
private let kAppGroup      = "group.com.fakelag.app"
private let kLagEnabledKey = "lagEnabled"
private let kLagPhaseKey   = "lagPhase"   // "ramp_up" | "peak" | "ramp_down" | "off"
private let kLagStartKey   = "lagStartTime"

// Lag profile:
//  0.0 – 1.0 s  →  ramp up: 0 → 600 ms delay  (tăng dần)
//  1.0 – 3.0 s  →  peak:    600 ms delay        (giữ nguyên, địch cảm giác lag nặng)
//  3.0 – 4.0 s  →  ramp down: 600 → 0 ms       (giảm dần)
//  > 4.0 s      →  off (tự động)

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var lagEnabled: Bool {
        UserDefaults(suiteName: kAppGroup)?.bool(forKey: kLagEnabledKey) ?? false
    }

    /// Returns current delay in milliseconds.
    /// Produces a constant ping spike of 900ms instantly when enabled.
    private var currentDelayMs: Int {
        return lagEnabled ? 900 : 0
    }

    // MARK: - Tunnel lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")

        // Capture ALL IPv4 traffic through the tunnel
        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // Also capture IPv6
        let ipv6 = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        // Use reliable DNS
        let dns = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4", "1.1.1.1"])
        settings.dnsSettings = dns

        settings.mtu = 1400

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
        packetFlow.readPacketObjects { [weak self] packetObjects in
            guard let self = self else { return }
            self.handlePacketObjects(packetObjects)
            self.startReadingPackets()
        }
    }

    private func handlePacketObjects(_ packetObjects: [NEPacket]) {
        guard !packetObjects.isEmpty else { return }

        let delay = currentDelayMs
        if delay > 0 {
            // Inject smooth variable delay matching the ping spike profile
            let delayNs = UInt64(delay) * 1_000_000
            let packets  = packetObjects.map { $0.data }
            let protos   = packetObjects.map { NSNumber(value: $0.protocolFamily) }
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + .nanoseconds(Int(delayNs))
            ) { [weak self] in
                self?.packetFlow.writePackets(packets, withProtocols: protos)
            }
        } else {
            // No delay — forward instantly
            let packets = packetObjects.map { $0.data }
            let protos  = packetObjects.map { NSNumber(value: $0.protocolFamily) }
            packetFlow.writePackets(packets, withProtocols: protos)

        }
    }
}
