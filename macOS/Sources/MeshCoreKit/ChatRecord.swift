import Foundation

public enum MessageDelivery: String, Codable, Sendable {
    case received, sending, awaitingAcknowledgement, acknowledged, accepted, unconfirmed, rejected
    public var label: String {
        switch self {
        case .received: return "Přijato"
        case .sending: return "Předávám companionu…"
        case .awaitingAcknowledgement: return "Čeká na potvrzení protějšku"
        case .acknowledged: return "Potvrzeno protějškem"
        case .accepted: return "Přijato companionem · bez potvrzení doručení"
        case .unconfirmed: return "Doručení neověřeno"
        case .rejected: return "Companion odmítl zprávu"
        }
    }
}
public struct ChatRecord: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public let conversationID: String
    public let title: String
    public let channelIndex: UInt8?
    public let peerPrefix: String?
    public let outgoing: Bool
    public let sender: String
    public let text: String
    public let timestamp: UInt32
    public var date = Date()
    public var delivery: MessageDelivery
    public var acknowledgement: UInt32?
    public var deadline: Date?
    public var roundTrip: UInt32?
    public var snr: Double?
    public var hops: Int?
    public var packetFingerprint: String?
    public var captures: [PacketCapture]? = nil
    public var capturedForwardings: Int?
    public var lastObservation: Date?
    public var observedRSSI: Int8?
    public var observedSNR: Double?
    public var seen: Bool
    public var detail: String?
    public var deduplicationID: String?
    public init(conversationID: String, title: String, channelIndex: UInt8? = nil, peerPrefix: String? = nil, outgoing: Bool, sender: String, text: String, timestamp: UInt32, delivery: MessageDelivery) {
        self.conversationID = conversationID; self.title = title; self.channelIndex = channelIndex; self.peerPrefix = peerPrefix; self.outgoing = outgoing; self.sender = sender; self.text = text; self.timestamp = timestamp; self.delivery = delivery; seen = outgoing
    }
}
