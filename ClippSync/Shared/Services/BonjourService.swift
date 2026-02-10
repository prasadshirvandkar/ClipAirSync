import Foundation
import Network
import Combine

#if os(iOS)
import UIKit
#endif

/// Discovered peer information
struct DiscoveredPeer: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.id == rhs.id
    }
}

/// Service for Bonjour discovery and advertisement
@MainActor
class BonjourService: ObservableObject {
    static let shared = BonjourService()
    
    /// Service type for ClipSync
    private let serviceType = "_clipsync._tcp"
    
    /// Default port
    private let defaultPort: UInt16 = 9876
    
    /// Network listener for accepting connections
    private var listener: NWListener?
    
    /// Network browser for discovering peers
    private var browser: NWBrowser?
    
    /// Published list of discovered peers
    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    
    /// Published connection status
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    
    /// Device name for advertisement
    private var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }
    
    /// Our own service name to filter out
    private var ownServiceName: String?
    
    /// Callback for new connections
    var onConnectionReceived: ((NWConnection) -> Void)?
    
    /// Callback for peer discovered
    var onPeerDiscovered: ((DiscoveredPeer) -> Void)?
    
    private init() {}
    
    // MARK: - Advertising
    
    /// Start advertising this device on the network
    func startAdvertising() {
        guard listener == nil else { return }
        
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: defaultPort) ?? .any)
            
            // Set up the service for Bonjour advertisement
            listener?.service = NWListener.Service(
                name: deviceName,
                type: serviceType
            )
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isAdvertising = true
                        self?.ownServiceName = self?.deviceName
                        print("BonjourService: Advertising as '\(self?.deviceName ?? "unknown")'")
                    case .failed(let error):
                        print("BonjourService: Listener failed: \(error)")
                        self?.isAdvertising = false
                    case .cancelled:
                        self?.isAdvertising = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("BonjourService: New connection received")
                Task { @MainActor in
                    self?.onConnectionReceived?(connection)
                }
            }
            
            listener?.start(queue: .main)
            
        } catch {
            print("BonjourService: Failed to create listener: \(error)")
        }
    }
    
    /// Stop advertising
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
    }
    
    // MARK: - Browsing
    
    /// Start browsing for other ClipSync devices
    func startBrowsing() {
        guard browser == nil else { return }
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: parameters
        )
        
        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isBrowsing = true
                    print("BonjourService: Browsing for peers")
                case .failed(let error):
                    print("BonjourService: Browser failed: \(error)")
                    self?.isBrowsing = false
                case .cancelled:
                    self?.isBrowsing = false
                default:
                    break
                }
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }
        
        browser?.start(queue: .main)
    }
    
    /// Stop browsing
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discoveredPeers.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var peers: [DiscoveredPeer] = []
        
        for result in results {
            if case .service(let name, let type, let domain, let interface) = result.endpoint {
                // Filter out our own service
                if name == ownServiceName {
                    continue
                }
                
                let peerId = "\(name).\(type).\(domain)"
                let peer = DiscoveredPeer(
                    id: peerId,
                    name: name,
                    endpoint: result.endpoint
                )
                peers.append(peer)
                print("BonjourService: Found peer '\(name)'")
            }
        }
        
        discoveredPeers = peers
        
        // Notify about new peers
        for peer in peers {
            onPeerDiscovered?(peer)
        }
    }
    
    /// Create a connection to a discovered peer
    func connect(to peer: DiscoveredPeer) -> NWConnection {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        
        let connection = NWConnection(to: peer.endpoint, using: parameters)
        return connection
    }
}
