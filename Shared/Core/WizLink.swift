import Darwin
import Foundation

/// Talks to WiZ lights directly over the home Wi-Fi. WiZ lights listen for short messages on port 38899
/// and answer straight away, so nothing goes through the internet or WiZ's servers.
///
/// Lumen finds lights by asking every address on the home network in turn (rather than one broadcast
/// shout, which iOS only allows for apps with special approval).
enum WizLink {
    static let port: UInt16 = 38899
    private static let queue = DispatchQueue(label: "lumen.wiz", qos: .userInitiated, attributes: .concurrent)

    /// Set in demo mode and screenshots: nothing is sent.
    nonisolated(unsafe) static var offline = false

    // MARK: Requests

    /// Sends one message and waits for the light's answer, trying a few times because Wi-Fi drops the odd message.
    static func request(_ method: String, params: [String: Any] = [:], to address: String,
                        timeout: TimeInterval = 0.45, attempts: Int = 3) async -> [String: Any]? {
        if offline { return nil }
        guard let payload = message(method, params) else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: exchange(payload, address: address, timeout: timeout, attempts: attempts))
            }
        }
    }

    /// Sends a message without waiting for an answer (used while a slider is being dragged).
    static func fire(_ method: String, params: [String: Any], to address: String) {
        if offline { return }
        guard let payload = message(method, params) else { return }
        queue.async {
            let socket = UDPSocket()
            socket?.send(payload, to: address, port: port)
        }
    }

    static func getPilot(_ address: String) async -> [String: Any]? {
        await request("getPilot", to: address)?["result"] as? [String: Any]
    }

    @discardableResult
    static func setPilot(_ params: [String: Any], on address: String) async -> Bool {
        let reply = await request("setPilot", params: params, to: address)
        return (reply?["result"] as? [String: Any])?["success"] as? Bool ?? false
    }

    // MARK: Finding lights

    struct Found: Hashable {
        let address: String
        let mac: String
        let pilot: [String: AnyHashable]
    }

    /// Asks every address on the home network whether it's a WiZ light. Takes a second or two.
    static func discover(extraAddresses: [String] = [], rounds: Int = 2) async -> [Found] {
        if offline { return [] }
        var targets = LocalNetwork.neighbourAddresses()
        for extra in extraAddresses where !targets.contains(extra) { targets.append(extra) }
        guard !targets.isEmpty, let payload = message("getPilot", [:]) else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: sweep(payload, targets: targets, rounds: rounds))
            }
        }
    }

    /// Details that don't change: the model name (which says whether it does colour) and its white range.
    struct Details {
        var model: String
        var minKelvin: Int
        var maxKelvin: Int
    }

    static func details(_ address: String) async -> Details? {
        guard let system = await request("getSystemConfig", to: address)?["result"] as? [String: Any] else { return nil }
        let model = system["moduleName"] as? String ?? ""
        var range: [Int] = []
        if let modelConfig = await request("getModelConfig", to: address, attempts: 2)?["result"] as? [String: Any] {
            range = numbers(modelConfig["cctRange"])
        }
        if range.isEmpty, let user = await request("getUserConfig", to: address, attempts: 2)?["result"] as? [String: Any] {
            range = numbers(user["extRange"])
            if range.isEmpty { range = numbers(user["whiteRange"]) }
        }
        let kind = LightKind(moduleName: model)
        let fallback = kind == .colour ? (2200, 6500) : (2700, 6500)
        let low = range.filter { $0 >= 1000 }.min() ?? fallback.0
        let high = range.filter { $0 <= 10000 }.max() ?? fallback.1
        return Details(model: model, minKelvin: low, maxKelvin: max(high, low + 100))
    }

    private static func numbers(_ value: Any?) -> [Int] {
        (value as? [Any])?.compactMap { ($0 as? Int) ?? ($0 as? Double).map { Int($0) } } ?? []
    }

    // MARK: Low level

    private static func message(_ method: String, _ params: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["method": method, "params": params], options: [.sortedKeys])
    }

    private static func exchange(_ payload: Data, address: String, timeout: TimeInterval, attempts: Int) -> [String: Any]? {
        guard let socket = UDPSocket() else { return nil }
        for _ in 0..<max(1, attempts) {
            guard socket.send(payload, to: address, port: port) else { continue }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                guard let (data, from) = socket.receive(timeout: deadline.timeIntervalSinceNow) else { break }
                guard from == address,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if object["error"] != nil { return object }
                if object["result"] != nil { return object }
            }
        }
        return nil
    }

    private static func sweep(_ payload: Data, targets: [String], rounds: Int) -> [Found] {
        guard let socket = UDPSocket() else { return [] }
        var found: [String: Found] = [:]

        func collect(until deadline: Date) {
            while Date() < deadline {
                guard let (data, from) = socket.receive(timeout: max(0.01, deadline.timeIntervalSinceNow)) else { return }
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = object["result"] as? [String: Any],
                      let mac = result["mac"] as? String else { continue }
                var pilot: [String: AnyHashable] = [:]
                for (key, value) in result { if let value = value as? AnyHashable { pilot[key] = value } }
                found[from] = Found(address: from, mac: mac.lowercased(), pilot: pilot)
            }
        }

        for _ in 0..<max(1, rounds) {
            for (index, target) in targets.enumerated() where found[target] == nil {
                socket.send(payload, to: target, port: port)
                // A tiny pause every few sends so the Wi-Fi chip isn't flooded.
                if index % 16 == 15 { collect(until: Date().addingTimeInterval(0.015)) }
            }
            collect(until: Date().addingTimeInterval(0.9))
        }
        return Array(found.values)
    }
}

/// A plain network socket for short messages.
final class UDPSocket {
    private let descriptor: Int32

    init?() {
        descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close(descriptor) }

    @discardableResult
    func send(_ data: Data, to address: String, port: UInt16) -> Bool {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        guard inet_pton(AF_INET, address, &target.sin_addr) == 1 else { return false }
        let sent = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == data.count
    }

    /// Waits up to `timeout` seconds for one message. Returns the message and who sent it.
    func receive(timeout: TimeInterval) -> (Data, String)? {
        let micro = max(1000, Int(timeout * 1_000_000))
        var wait = timeval(tv_sec: micro / 1_000_000, tv_usec: Int32(micro % 1_000_000))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        let capacity = 4096
        var buffer = [UInt8](repeating: 0, count: capacity)
        var source = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &source) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(descriptor, &buffer, capacity, 0, $0, &length)
            }
        }
        guard count > 0 else { return nil }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &source.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
        return (Data(buffer[0..<count]), String(cString: text))
    }
}

/// Works out which addresses are on the same home network as this phone.
enum LocalNetwork {
    struct Interface {
        let address: UInt32
        let mask: UInt32
        let name: String
    }

    static func wifiInterface() -> Interface? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [Interface] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(bitPattern: current.pointee.ifa_flags)
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let maskPointer = current.pointee.ifa_netmask,
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: current.pointee.ifa_name)
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            // Skip self-assigned addresses (169.254.x.x).
            if address >> 16 == 0xA9FE { continue }
            candidates.append(Interface(address: address, mask: mask, name: name))
        }
        // Wi-Fi is "en0" on the phone. Elsewhere (the simulator on a Mac) take the first private network.
        return candidates.first { $0.name == "en0" } ?? candidates.first { isPrivate($0.address) } ?? candidates.first
    }

    private static func isPrivate(_ address: UInt32) -> Bool {
        address >> 24 == 10 || address >> 20 == 0xAC1 || address >> 16 == 0xC0A8
    }

    /// Every other address on this network, nearest first. Very large networks are trimmed to the
    /// 1,024 addresses around this phone, which covers any normal home.
    static func neighbourAddresses() -> [String] {
        guard let interface = wifiInterface() else { return [] }
        var mask = interface.mask
        if mask == 0 || ~mask > 1023 { mask = 0xFFFF_FC00 }
        let network = interface.address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        let hosts = (network + 1)..<broadcast
        let sorted = hosts.sorted { abs(Int64($0) - Int64(interface.address)) < abs(Int64($1) - Int64(interface.address)) }
        return sorted.map(format)
    }

    static func ownAddress() -> String? { wifiInterface().map { format($0.address) } }

    static func format(_ value: UInt32) -> String {
        "\(value >> 24 & 0xFF).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    }
}
