import Foundation
import Network

#if os(macOS)
import AppKit
#endif

/// Monitors the system clipboard for changes (macOS only)
#if os(macOS)
class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    
    /// Device name for clipboard items
    private var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }
    
    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }
    
    /// Start monitoring clipboard changes
    func startMonitoring() {
        // Poll every 0.5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        // Check if clipboard has changed
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            // Get text content
            if let content = pasteboard.string(forType: .string), !content.isEmpty {
                Task { @MainActor in
                    ClipboardStore.shared.addItem(content: content, sourceDevice: self.deviceName)
                }
            }
        }
    }
}
#endif
