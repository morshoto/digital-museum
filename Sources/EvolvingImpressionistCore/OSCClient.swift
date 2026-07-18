import Foundation
import Network

public enum TransportStatus: Equatable, Sendable {
    case idle, connecting, ready, failed(String)

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .connecting: "Connecting"
        case .ready: "Ready"
        case .failed(let message): "Failed: \(message)"
        }
    }
}

public enum OSCMessageCodec {
    public static func encode(address: String, value: Float) -> Data {
        var data = Data()
        data.append(padded(Data(address.utf8)))
        data.append(padded(Data(",f".utf8)))
        var bits = value.bitPattern.bigEndian
        data.append(Data(bytes: &bits, count: 4))
        return data
    }

    public static func decode(_ data: Data) -> (address: String, value: Float)? {
        guard let addressEnd = data.firstIndex(of: 0),
              let address = String(data: data[..<addressEnd], encoding: .utf8) else { return nil }
        let typeOffset = paddedLength(addressEnd + 1)
        guard typeOffset < data.count,
              let typeEnd = data[typeOffset...].firstIndex(of: 0),
              String(data: data[typeOffset..<typeEnd], encoding: .utf8) == ",f" else { return nil }
        let valueOffset = typeOffset + paddedLength(typeEnd - typeOffset + 1)
        guard data.count >= valueOffset + 4 else { return nil }
        let bits = data[valueOffset..<(valueOffset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return (address, Float(bitPattern: bits))
    }

    private static func padded(_ input: Data) -> Data {
        var output = input + Data([0])
        while output.count % 4 != 0 { output.append(0) }
        return output
    }

    private static func paddedLength(_ length: Int) -> Int { ((length + 3) / 4) * 4 }
}

@MainActor
public final class OSCClient: ObservableObject {
    @Published public private(set) var status: TransportStatus = .idle
    @Published public private(set) var sentMessageCount = 0

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "evolving-impressionist.osc")

    public init(host: String = "127.0.0.1", port: UInt16 = 57120) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        status = .connecting
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.status = .ready
                case .failed(let error): self?.status = .failed(error.localizedDescription)
                case .cancelled: self?.status = .idle
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }

    public func send(state: WorldState) {
        for parameter in WorldParameter.allCases {
            let message = OSCMessageCodec.encode(address: "/\(parameter.rawValue)", value: Float(state[parameter]))
            connection.send(content: message, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    if let error { self?.status = .failed(error.localizedDescription) }
                    else { self?.sentMessageCount += 1 }
                }
            })
        }
    }

    public func cancel() { connection.cancel() }
}
