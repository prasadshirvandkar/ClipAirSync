import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

import Combine

@main
struct ClipSyncApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    #endif
    
    var body: some Scene {
        #if os(macOS)
        // macOS: Menu bar only, no main window
        Settings {
            EmptyView()
        }
        #else
        // iOS: Standard window
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.setupServices()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appState.onBecomeActive()
                    }
                }
        }
        #endif
    }
}

// MARK: - macOS App Delegate

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var clipboardMonitor: ClipboardMonitor?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Set up menu bar
        setupMenuBar()
        
        // Start clipboard monitoring
        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor?.startMonitoring()
        
        // Set up network services
        setupNetworkServices()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipSync")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 480)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView())
    }
    
    private func setupNetworkServices() {
        Task { @MainActor in
            let bonjourService = BonjourService.shared
            let networkService = NetworkService.shared
            let store = ClipboardStore.shared
            
            // Start advertising and browsing
            bonjourService.startAdvertising()
            bonjourService.startBrowsing()
            
            // Handle incoming connections
            bonjourService.onConnectionReceived = { connection in
                networkService.handleIncomingConnection(connection)
            }
            
            // Auto-connect to discovered peers
            bonjourService.onPeerDiscovered = { peer in
                networkService.connectToPeer(peer)
            }
            
            // Handle received clipboard items
            networkService.onClipboardItemReceived = { item in
                Task { @MainActor in
                    store.addItemFromNetwork(item)
                }
            }
            
            // Handle sync requests
            networkService.onSyncRequestReceived = { connection in
                Task { @MainActor in
                    networkService.sendSyncResponse(to: connection, items: store.items)
                }
            }
            
            // Broadcast new clipboard items
            store.onItemAdded = { item in
                networkService.broadcastClipboardItem(item)
            }
        }
    }
    
    @objc private func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover?.contentViewController?.view.window?.makeKey()
            }
        }
    }
}
#endif

// MARK: - iOS App State

#if os(iOS)
@MainActor
class AppState: ObservableObject {
    @Published var showingAddedToast = false
    
    private var hasSetup = false
    
    func setupServices() {
        guard !hasSetup else { return }
        hasSetup = true
        
        let bonjourService = BonjourService.shared
        let networkService = NetworkService.shared
        let store = ClipboardStore.shared
        
        // Start advertising and browsing
        bonjourService.startAdvertising()
        bonjourService.startBrowsing()
        
        // Handle incoming connections
        bonjourService.onConnectionReceived = { connection in
            networkService.handleIncomingConnection(connection)
        }
        
        // Auto-connect to discovered peers
        bonjourService.onPeerDiscovered = { peer in
            networkService.connectToPeer(peer)
        }
        
        // Handle received clipboard items
        networkService.onClipboardItemReceived = { item in
            Task { @MainActor in
                store.addItemFromNetwork(item)
            }
        }
        
        // Handle sync requests
        networkService.onSyncRequestReceived = { connection in
            Task { @MainActor in
                networkService.sendSyncResponse(to: connection, items: store.items)
            }
        }
        
        // Broadcast new clipboard items
        store.onItemAdded = { item in
            networkService.broadcastClipboardItem(item)
        }
    }
    
    func onBecomeActive() {
        NetworkService.shared.requestSync()
    }
    
    func addFromClipboard() {
        if let content = UIPasteboard.general.string, !content.isEmpty {
            let deviceName = UIDevice.current.name
            ClipboardStore.shared.addItem(content: content, sourceDevice: deviceName)
            
            showingAddedToast = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    showingAddedToast = false
                }
            }
        }
    }
}
#endif
