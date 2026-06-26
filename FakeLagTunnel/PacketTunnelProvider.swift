import NetworkExtension
import Foundation
import Network

// MARK: - Shared lag state via UserDefaults App Group
private var kAppGroup: String {
    if let extID = Bundle.main.bundleIdentifier {
        let cleanID = extID.replacingOccurrences(of: ".tunnel", with: "")
                           .replacingOccurrences(of: ".FakeLagTunnel", with: "")
        return "group.\(cleanID)"
    }
    return "group.com.fakelag.app"
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var socksServer: Socks5Server?
    private var udpForwarder: UDPForwarder?
    private let packetQueue = DispatchQueue(label: "com.fakelag.packetqueue", qos: .userInteractive)

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")

        // Capture IPv4 traffic
        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "127.0.0.1", subnetMask: "255.255.255.255"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0")
        ]
        settings.ipv4Settings = ipv4

        // Capture IPv6
        let ipv6 = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        // Set reliable DNS (with delay capability handled in UDP forwarder)
        let dns = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4", "1.1.1.1"])
        settings.dnsSettings = dns

        // Configure SOCKS Proxy settings using PAC script to transparently capture TCP traffic
        let proxy = NEProxySettings()
        proxy.autoConfigurationJavaScript = "function FindProxyForURL(url, host) { return 'SOCKS5 127.0.0.1:1080; SOCKS 127.0.0.1:1080; DIRECT'; }"
        proxy.exceptionList = ["127.0.0.1", "localhost", "*.local"]
        settings.proxySettings = proxy

        settings.mtu = 1400

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completionHandler(error)
                return
            }

            // Start SOCKS5 Server on port 1080
            do {
                self.socksServer = Socks5Server()
                try self.socksServer?.start(port: 1080)
            } catch {
                NSLog("[FakeLag] Failed to start Socks5Server: \(error)")
            }

            // Start UDP NAT Forwarder
            self.udpForwarder = UDPForwarder(appGroup: kAppGroup, queue: self.packetQueue) { [weak self] packet in
                self?.packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
            }

            completionHandler(nil)
            self.startReadingPackets()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        socksServer?.stop()
        socksServer = nil
        udpForwarder?.stop()
        udpForwarder = nil
        completionHandler()
    }

    private func startReadingPackets() {
        packetFlow.readPacketObjects { [weak self] packetObjects in
            guard let self = self else { return }
            self.packetQueue.async {
                self.handlePacketObjects(packetObjects)
            }
            self.startReadingPackets()
        }
    }

    private func handlePacketObjects(_ packetObjects: [NEPacket]) {
        for packet in packetObjects {
            udpForwarder?.handleOutboundPacket(packet.data)
        }
    }
}

// MARK: - Socks5 Server Implementation
class Socks5Server {
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    func start(port: UInt16) throws {
        let params = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: .global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections.values {
            conn.cancel()
        }
        connections.removeAll()
    }

    private func handleConnection(_ client: NWConnection) {
        let id = UUID()
        connections[id] = client
        client.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                self?.connections.removeValue(forKey: id)
            } else if case .failed = state {
                self?.connections.removeValue(forKey: id)
            }
        }
        client.start(queue: .global())
        readHandshake(client, id: id)
    }

    private func readHandshake(_ client: NWConnection, id: UUID) {
        client.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] (data, _, _, error) in
            guard let self = self, error == nil, let data = data, data.count == 2 else {
                client.cancel()
                return
            }
            let version = data[0]
            let numMethods = Int(data[1])
            guard version == 0x05 else {
                client.cancel()
                return
            }

            client.receive(minimumIncompleteLength: numMethods, maximumLength: numMethods) { [weak self] (_, _, _, error) in
                guard let self = self, error == nil else {
                    client.cancel()
                    return
                }

                // Reply: No Authentication Required (0x05, 0x00)
                let response = Data([0x05, 0x00])
                client.send(content: response, completion: .contentProcessed({ [weak self] error in
                    if error == nil {
                        self?.readRequest(client, id: id)
                    } else {
                        client.cancel()
                    }
                }))
            }
        }
    }

    private func readRequest(_ client: NWConnection, id: UUID) {
        client.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] (data, _, _, error) in
            guard let self = self, error == nil, let data = data, data.count == 4 else {
                client.cancel()
                return
            }
            let version = data[0]
            let cmd = data[1]
            let atyp = data[3]

            guard version == 0x05, cmd == 0x01 else {
                client.cancel()
                return
            }

            if atyp == 0x01 { // IPv4 address
                client.receive(minimumIncompleteLength: 6, maximumLength: 6) { [weak self] (addrPortData, _, _, error) in
                    guard let self = self, error == nil, let addrPortData = addrPortData, addrPortData.count == 6 else {
                        client.cancel()
                        return
                    }
                    let ip = addrPortData.subdata(in: 0..<4)
                    let port = UInt16(addrPortData[4]) << 8 | UInt16(addrPortData[5])
                    let ipString = "\(ip[0]).\(ip[1]).\(ip[2]).\(ip[3])"
                    self.connectToDestination(client, host: ipString, port: port, id: id)
                }
            } else if atyp == 0x03 { // Domain Name
                client.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] (lenData, _, _, error) in
                    guard let self = self, error == nil, let lenData = lenData, lenData.count == 1 else {
                        client.cancel()
                        return
                    }
                    let domainLen = Int(lenData[0])
                    client.receive(minimumIncompleteLength: domainLen + 2, maximumLength: domainLen + 2) { [weak self] (domainPortData, _, _, error) in
                        guard let self = self, error == nil, let domainPortData = domainPortData, domainPortData.count == domainLen + 2 else {
                            client.cancel()
                            return
                        }
                        let domainData = domainPortData.subdata(in: 0..<domainLen)
                        let domainString = String(data: domainData, encoding: .utf8) ?? ""
                        let portHigh = domainPortData[domainLen]
                        let portLow = domainPortData[domainLen + 1]
                        let port = UInt16(portHigh) << 8 | UInt16(portLow)
                        self.connectToDestination(client, host: domainString, port: port, id: id)
                    }
                }
            } else {
                client.cancel()
            }
        }
    }

    private func connectToDestination(_ client: NWConnection, host: String, port: UInt16, id: UUID) {
        let destEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let destConn = NWConnection(to: destEndpoint, using: .tcp)

        destConn.stateUpdateHandler = { [weak self, weak client, weak destConn] state in
            guard let self = self, let client = client, let destConn = destConn else { return }
            switch state {
            case .ready:
                // Success Response (0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0)
                let successResponse = Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                client.send(content: successResponse, completion: .contentProcessed({ [weak self] error in
                    if error == nil {
                        self?.pipe(from: client, to: destConn)
                        self?.pipe(from: destConn, to: client)
                    } else {
                        client.cancel()
                        destConn.cancel()
                    }
                }))
            case .failed, .cancelled:
                client.cancel()
                destConn.cancel()
            default:
                break
            }
        }
        destConn.start(queue: .global())
    }

    private func pipe(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak from, weak to, weak self] (data, _, isComplete, error) in
            guard let self = self, let from = from, let to = to else { return }
            if let data = data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed({ [weak from, weak to, weak self] error in
                    if error == nil {
                        if let f = from, let t = to {
                            self?.pipe(from: f, to: t)
                        }
                    } else {
                        from?.cancel()
                        to?.cancel()
                    }
                }))
            } else if isComplete {
                to.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
            } else if error != nil {
                from.cancel()
                to.cancel()
            } else {
                self.pipe(from: from, to: to)
            }
        }
    }
}

// MARK: - UDP Forwarder Implementation
class UDPForwarder {
    private var sessions: [String: NWConnection] = [:]
    private var writeQueue: DispatchQueue
    private var writePacketHandler: (Data) -> Void
    private var kAppGroup: String

    init(appGroup: String, queue: DispatchQueue, writeHandler: @escaping (Data) -> Void) {
        self.kAppGroup = appGroup
        self.writeQueue = queue
        self.writePacketHandler = writeHandler
    }

    private var lagEnabled: Bool {
        UserDefaults(suiteName: kAppGroup)?.bool(forKey: "lagEnabled") ?? false
    }

    func stop() {
        for conn in sessions.values {
            conn.cancel()
        }
        sessions.removeAll()
    }

    func handleOutboundPacket(_ packet: Data) {
        guard packet.count >= 28 else { return } // IP Header (20) + UDP Header (8)

        let ipHeaderLen = Int(packet[0] & 0x0F) * 4
        guard packet.count >= ipHeaderLen + 8 else { return }

        // Must be UDP (17)
        guard packet[9] == 17 else { return }

        // Source IP must match local virtual IP (10.0.0.2)
        let srcIP = packet.subdata(in: 12..<16)
        guard srcIP == Data([10, 0, 0, 2]) else { return }

        // Destination IP
        let destIP = packet.subdata(in: 16..<20)
        let destIPString = "\(destIP[0]).\(destIP[1]).\(destIP[2]).\(destIP[3])"

        // UDP Ports
        let srcPort = UInt16(packet[ipHeaderLen]) << 8 | UInt16(packet[ipHeaderLen + 1])
        let destPort = UInt16(packet[ipHeaderLen + 2]) << 8 | UInt16(packet[ipHeaderLen + 3])

        let udpLen = UInt16(packet[ipHeaderLen + 4]) << 8 | UInt16(packet[ipHeaderLen + 5])
        let payloadLen = Int(udpLen) - 8
        guard payloadLen > 0, packet.count >= ipHeaderLen + 8 + payloadLen else { return }

        let payload = packet.subdata(in: (ipHeaderLen + 8)..<(ipHeaderLen + 8 + payloadLen))

        // Outbound packet loss simulation (10% drop chance)
        if lagEnabled {
            let randomVal = Int.random(in: 1...100)
            if randomVal <= 10 {
                return // Drop packet
            }
        }

        // Apply DNS Delay: 10ms delay if port is 53 (DNS)
        let isDNS = (destPort == 53)
        let delayMs = (lagEnabled && isDNS) ? 10 : 0

        if delayMs > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
                self?.sendPayload(payload, srcIP: srcIP, destIP: destIP, srcPort: srcPort, destPort: destPort, destIPString: destIPString)
            }
        } else {
            sendPayload(payload, srcIP: srcIP, destIP: destIP, srcPort: srcPort, destPort: destPort, destIPString: destIPString)
        }
    }

    private func sendPayload(_ payload: Data, srcIP: Data, destIP: Data, srcPort: UInt16, destPort: UInt16, destIPString: String) {
        let key = "\(srcPort)"
        let connection: NWConnection

        if let existing = sessions[key] {
            connection = existing
        } else {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(destIPString), port: NWEndpoint.Port(rawValue: destPort)!)
            connection = NWConnection(to: endpoint, using: .udp)
            sessions[key] = connection

            listenForReplies(connection, key: key, srcIP: srcIP, destIP: destIP, srcPort: srcPort, destPort: destPort)
            connection.start(queue: .global())
        }

        connection.send(content: payload, completion: .contentProcessed({ _ in }))
    }

    private func listenForReplies(_ connection: NWConnection, key: String, srcIP: Data, destIP: Data, srcPort: UInt16, destPort: UInt16) {
        connection.receiveMessage { [weak self, weak connection] (data, _, _, error) in
            guard let self = self, let connection = connection, error == nil else {
                if error != nil {
                    self?.sessions.removeValue(forKey: key)
                }
                return
            }

            if let replyData = data, !replyData.isEmpty {
                // Inbound packet loss simulation (100% drop chance)
                if self.lagEnabled {
                    // Drop all inbound gameplay packets (enemies freeze)
                    self.listenForReplies(connection, key: key, srcIP: srcIP, destIP: destIP, srcPort: srcPort, destPort: destPort)
                    return
                }

                // Delay inbound packets by 10ms (base latency simulation)
                let delayMs = 10
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
                    guard let self = self else { return }
                    // Wrap back as IP/UDP packet
                    let packet = self.makeIPUDPPacket(srcIP: destIP, destIP: srcIP, srcPort: destPort, destPort: srcPort, payload: replyData)
                    self.writePacketHandler(packet)
                }
            }

            self.listenForReplies(connection, key: key, srcIP: srcIP, destIP: destIP, srcPort: srcPort, destPort: destPort)
        }
    }

    private func makeIPUDPPacket(srcIP: Data, destIP: Data, srcPort: UInt16, destPort: UInt16, payload: Data) -> Data {
        let ipHeaderLength = 20
        let udpHeaderLength = 8
        let totalLength = ipHeaderLength + udpHeaderLength + payload.count

        var packet = Data(repeating: 0, count: totalLength)

        // Version & IHL
        packet[0] = 0x45
        // TOS
        packet[1] = 0x00
        // Total Length
        packet[2] = UInt8((totalLength >> 8) & 0xFF)
        packet[3] = UInt8(totalLength & 0xFF)
        // Identification
        packet[4] = 0x00
        packet[5] = 0x00
        // Flags (Don't Fragment)
        packet[6] = 0x40
        packet[7] = 0x00
        // TTL
        packet[8] = 64
        // Protocol (UDP = 17)
        packet[9] = 17

        // Source IP
        packet[12...15] = srcIP
        // Destination IP
        packet[16...19] = destIP

        // IP Header Checksum
        let checksum = calculateChecksum(data: packet.subdata(in: 0..<20))
        packet[10] = UInt8((checksum >> 8) & 0xFF)
        packet[11] = UInt8(checksum & 0xFF)

        // UDP Ports
        let spBytes = withUnsafeBytes(of: srcPort.bigEndian) { Data($0) }
        let dpBytes = withUnsafeBytes(of: destPort.bigEndian) { Data($0) }
        packet[20...21] = spBytes
        packet[22...23] = dpBytes

        // UDP Length
        let udpLength = udpHeaderLength + payload.count
        let lenBytes = withUnsafeBytes(of: UInt16(udpLength).bigEndian) { Data($0) }
        packet[24...25] = lenBytes

        // UDP Checksum (0 means ignored/no checksum in IPv4 UDP)
        packet[26] = 0x00
        packet[27] = 0x00

        // Payload
        packet[28...] = payload

        return packet
    }

    private func calculateChecksum(data: Data) -> UInt16 {
        var sum: UInt32 = 0
        let count = data.count
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let typedBytes = bytes.bindMemory(to: UInt16.self)
            for i in 0..<(count / 2) {
                sum += UInt32(UInt16(bigEndian: typedBytes[i]))
            }
        }
        if count % 2 != 0 {
            sum += UInt32(data[count - 1]) << 8
        }
        while (sum >> 16) > 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return UInt16(~sum)
    }
}
