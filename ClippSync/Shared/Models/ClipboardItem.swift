import Foundation
import CryptoKit

/// Represents a single clipboard item that can be synced across devices
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var timestamp: Date
    let sourceDevice: String
    let contentHash: String
    
    init(content: String, sourceDevice: String) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.sourceDevice = sourceDevice
        self.contentHash = ClipboardItem.hash(for: content)
    }
    
    /// Creates a SHA256 hash of the content for deduplication
    static func hash(for content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
    
    /// Preview of the content for display (first 100 characters)
    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 100 {
            return String(trimmed.prefix(100)) + "..."
        }
        return trimmed
    }
    
    /// Formatted timestamp for display
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Network Message Types

/// Message types for network protocol
enum MessageType: String, Codable {
    case clipboardItem = "clipboard_item"
    case syncRequest = "sync_request"
    case syncResponse = "sync_response"
    case heartbeat = "heartbeat"
}

/// Network message wrapper
struct NetworkMessage: Codable {
    let type: MessageType
    let payload: Data?
    
    init(type: MessageType, payload: Codable? = nil) {
        self.type = type
        if let payload = payload {
            self.payload = try? JSONEncoder().encode(payload)
        } else {
            self.payload = nil
        }
    }
    
    func decodePayload<T: Codable>(_ type: T.Type) -> T? {
        guard let data = payload else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Sync response containing all clipboard items
struct SyncResponsePayload: Codable {
    let items: [ClipboardItem]
}
