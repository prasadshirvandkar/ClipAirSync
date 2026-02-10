import Foundation
import Network
import Combine

/// Manages network connections and message exchange between peers
@MainActor
class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    /// Active connections to peers
    private var connections: [String: NWConnection] = [:]
    
    /// Published connection count
    @Published private(set) var connectedPeerCount = 0
    @Published private(set) var connectedPeerNames: [String] = []
    
    /// Callback for received clipboard items
    var onClipboardItemReceived: ((ClipboardItem) -> Void)?
    
    /// Callback for sync request
    var onSyncRequestReceived: ((NWConnection) -> Void)?
    
    private init() {}
    
    // MARK: - Connection Management
    
    /// Handle an incoming connection
    func handleIncomingConnection(_ connection: NWConnection) {
        let connectionId = UUID().uuidString
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, connectionId: connectionId, connection: connection)
            }
        }
        
        connection.start(queue: .main)
        receiveMessage(on: connection, connectionId: connectionId)
    }
    
    /// Connect to a discovered peer
    func connectToPeer(_ peer: DiscoveredPeer) {
        // Check if already connected
        if connections[peer.id] != nil {
            return
        }
        
        let connection = BonjourService.shared.connect(to: peer)
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, connectionId: peer.id, connection: connection, peerName: peer.name)
            }
        }
        
        connection.start(queue: .main)
        receiveMessage(on: connection, connectionId: peer.id)
    }
    
    /// Disconnect from a peer
    func disconnectFromPeer(id: String) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        updateConnectionStatus()
    }
    
    /// Disconnect all peers
    func disconnectAll() {
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        updateConnectionStatus()
    }
    
    // MARK: - Sending Messages
    
    /// Send a clipboard item to all connected peers
    func broadcastClipboardItem(_ item: ClipboardItem) {
        let message = NetworkMessage(type: .clipboardItem, payload: item)
        broadcastMessage(message)
    }
    
    /// Send a sync request to all connected peers
    func requestSync() {
        let message = NetworkMessage(type: .syncRequest)
        broadcastMessage(message)
    }
    
    /// Send sync response to a specific connection
    func sendSyncResponse(to connection: NWConnection, items: [ClipboardItem]) {
        let payload = SyncResponsePayload(items: items)
        let message = NetworkMessage(type: .syncResponse, payload: payload)
        sendMessage(message, on: connection)
    }
    
    /// Send heartbeat to all peers
    func sendHeartbeat() {
        let message = NetworkMessage(type: .heartbeat)
        broadcastMessage(message)
    }
    
    // MARK: - Private Methods
    
    private func handleConnectionState(_ state: NWConnection.State, connectionId: String, connection: NWConnection, peerName: String? = nil) {
        switch state {
        case .ready:
            connections[connectionId] = connection
            print("NetworkService: Connected to peer \(peerName ?? connectionId)")
            updateConnectionStatus()
            
            // Request sync on new connection
            sendMessage(NetworkMessage(type: .syncRequest), on: connection)
            
        case .failed(let error):
            print("NetworkService: Connection failed: \(error)")
            connections.removeValue(forKey: connectionId)
            updateConnectionStatus()
            
        case .cancelled:
            connections.removeValue(forKey: connectionId)
            updateConnectionStatus()
            
        default:
            break
        }
    }
    
    private func updateConnectionStatus() {
        connectedPeerCount = connections.count
        // Extract peer names from BonjourService discovered peers
        connectedPeerNames = BonjourService.shared.discoveredPeers
            .filter { connections[$0.id] != nil }
            .map { $0.name }
    }
    
    private func broadcastMessage(_ message: NetworkMessage) {
        for (_, connection) in connections {
            sendMessage(message, on: connection)
        }
    }
    
    private func sendMessage(_ message: NetworkMessage, on connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message) else {
            print("NetworkService: Failed to encode message")
            return
        }
        
        // Frame the message with length prefix (4 bytes)
        var length = UInt32(data.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(data)
        
        connection.send(content: framedData, completion: .contentProcessed { error in
            if let error = error {
                print("NetworkService: Send error: \(error)")
            }
        })
    }
    
    private func receiveMessage(on connection: NWConnection, connectionId: String) {
        // First, receive the 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("NetworkService: Receive error: \(error)")
                return
            }
            
            if isComplete {
                Task { @MainActor in
                    self?.connections.removeValue(forKey: connectionId)
                    self?.updateConnectionStatus()
                }
                return
            }
            
            guard let lengthData = data, lengthData.count == 4 else {
                // Continue receiving
                Task { @MainActor in
                    self?.receiveMessage(on: connection, connectionId: connectionId)
                }
                return
            }
            
            // Parse length
            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // Receive the message body
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] messageData, _, _, error in
                if let error = error {
                    print("NetworkService: Receive body error: \(error)")
                    return
                }
                
                if let messageData = messageData {
                    Task { @MainActor in
                        self?.handleReceivedData(messageData, from: connection)
                    }
                }
                
                // Continue receiving
                Task { @MainActor in
                    self?.receiveMessage(on: connection, connectionId: connectionId)
                }
            }
        }
    }
    
    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        guard let message = try? JSONDecoder().decode(NetworkMessage.self, from: data) else {
            print("NetworkService: Failed to decode message")
            return
        }
        
        switch message.type {
        case .clipboardItem:
            if let item = message.decodePayload(ClipboardItem.self) {
                print("NetworkService: Received clipboard item from \(item.sourceDevice)")
                onClipboardItemReceived?(item)
            }
            
        case .syncRequest:
            print("NetworkService: Received sync request")
            onSyncRequestReceived?(connection)
            
        case .syncResponse:
            if let response = message.decodePayload(SyncResponsePayload.self) {
                print("NetworkService: Received sync response with \(response.items.count) items")
                for item in response.items {
                    onClipboardItemReceived?(item)
                }
            }
            
        case .heartbeat:
            // Just keep connection alive
            break
        }
    }
}
