import Foundation
import Network

final class OSCClient {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "evolving-impressionist.osc")

    init(host: String = "127.0.0.1", port: UInt16 = 57120) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        connection.start(queue: queue)
    }

    func send(state: WorldState) {
        for parameter in WorldParameter.allCases {
            let message = Self.message(address: "/\(parameter.rawValue)", value: Float(state[parameter]))
            connection.send(content: message, completion: .contentProcessed { _ in })
        }
    }

    private static func message(address: String, value: Float) -> Data {
        var data = Data()
        data.append(padded(address.data(using: .utf8)!))
        data.append(padded(" ,f".replacingOccurrences(of: " ", with: "").data(using: .utf8)!))
        var bits = value.bitPattern.bigEndian
        data.append(Data(bytes: &bits, count: 4))
        return data
    }

    private static func padded(_ input: Data) -> Data {
        var output = input + Data([0])
        while output.count % 4 != 0 { output.append(0) }
        return output
    }
}
