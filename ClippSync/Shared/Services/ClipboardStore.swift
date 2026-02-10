import Foundation
import SwiftUI
import Combine

/// Manages the clipboard history and persistence
@MainActor
class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()
    
    /// Maximum number of items to store
    private let maxItems = 50
    
    /// Key for UserDefaults storage
    private let storageKey = "clipboardItems"
    
    /// Published list of clipboard items
    @Published private(set) var items: [ClipboardItem] = []
    
    /// Callback when a new item is added (for network sync)
    var onItemAdded: ((ClipboardItem) -> Void)?
    
    private init() {
        loadItems()
    }
    
    // MARK: - Public Methods
    
    /// Adds a new item to the store, updating timestamp if duplicate content exists
    func addItem(_ item: ClipboardItem) {
        // Check for duplicate content via hash
        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            // Update timestamp of existing item and move to top
            var updatedItem = items[existingIndex]
            updatedItem.timestamp = Date()
            items.remove(at: existingIndex)
            items.insert(updatedItem, at: 0)
        } else {
            // Add new item at the beginning
            items.insert(item, at: 0)
            
            // Trim to max items
            if items.count > maxItems {
                items = Array(items.prefix(maxItems))
            }
        }
        
        saveItems()
        onItemAdded?(item)
    }
    
    /// Adds a new item from content string
    func addItem(content: String, sourceDevice: String) {
        let item = ClipboardItem(content: content, sourceDevice: sourceDevice)
        addItem(item)
    }
    
    /// Adds item from network (doesn't trigger onItemAdded to avoid loops)
    func addItemFromNetwork(_ item: ClipboardItem) {
        // Check for duplicate content via hash
        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            // Update if network item is newer
            if item.timestamp > items[existingIndex].timestamp {
                var updatedItem = items[existingIndex]
                updatedItem.timestamp = item.timestamp
                items.remove(at: existingIndex)
                items.insert(updatedItem, at: 0)
                saveItems()
            }
        } else {
            // Add new item at the beginning
            items.insert(item, at: 0)
            
            // Sort by timestamp (most recent first)
            items.sort { $0.timestamp > $1.timestamp }
            
            // Trim to max items
            if items.count > maxItems {
                items = Array(items.prefix(maxItems))
            }
            
            saveItems()
        }
    }
    
    /// Merges items from a sync response
    func mergeItems(_ newItems: [ClipboardItem]) {
        for item in newItems {
            addItemFromNetwork(item)
        }
    }
    
    /// Removes an item at the specified index
    func removeItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
        saveItems()
    }
    
    /// Removes an item by ID
    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        saveItems()
    }
    
    /// Clears all items
    func clearAll() {
        items.removeAll()
        saveItems()
    }
    
    // MARK: - Persistence
    
    private func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loadedItems = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = loadedItems
        }
    }
}
