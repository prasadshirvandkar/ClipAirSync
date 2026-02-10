import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    #if os(iOS)
    @EnvironmentObject var appState: AppState
    #endif
    
    @ObservedObject private var store = ClipboardStore.shared
    @ObservedObject private var bonjourService = BonjourService.shared
    @ObservedObject private var networkService = NetworkService.shared
    
    @State private var copiedItemId: UUID? = nil
    
    var body: some View {
        #if os(macOS)
        macOSView
        #else
        iOSView
        #endif
    }
    
    // MARK: - iOS View
    
    #if os(iOS)
    private var iOSView: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    connectionStatusBar
                    
                    if store.items.isEmpty {
                        emptyStateView
                    } else {
                        clipboardListView
                    }
                }
                
                VStack {
                    Spacer()
                    addFromClipboardButton
                        .padding(.bottom, 20)
                }
                
                if appState.showingAddedToast {
                    toastView
                }
            }
            .navigationTitle("ClipSync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive, action: { store.clearAll() }) {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var addFromClipboardButton: some View {
        Button(action: { appState.addFromClipboard() }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add from Clipboard")
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
        }
    }
    
    private var toastView: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Added to history")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: appState.showingAddedToast)
    }
    #endif
    
    // MARK: - macOS View
    
    #if os(macOS)
    private var macOSView: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            if store.items.isEmpty {
                emptyStateView
            } else {
                clipboardListView
            }
            
            Divider()
            footerView
        }
        .frame(width: 360, height: 480)
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundColor(.accentColor)
            
            Text("ClipSync")
                .font(.headline)
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(networkService.connectedPeerCount > 0 ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(connectionStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private var footerView: some View {
        HStack {
            Button(action: { store.clearAll() }) {
                Text("Clear All")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    #endif
    
    // MARK: - Shared Views
    
    private var connectionStatusBar: some View {
        HStack {
            Circle()
                .fill(networkService.connectedPeerCount > 0 ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            Text(connectionStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if bonjourService.isBrowsing && networkService.connectedPeerCount == 0 {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var connectionStatusText: String {
        if networkService.connectedPeerCount == 0 {
            return bonjourService.isBrowsing ? "Searching for devices..." : "Offline"
        } else if networkService.connectedPeerCount == 1 {
            return "Connected to \(networkService.connectedPeerNames.first ?? "1 device")"
        } else {
            return "Connected to \(networkService.connectedPeerCount) devices"
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No Clipboard History")
                .font(.title2)
                .fontWeight(.semibold)
            
            #if os(iOS)
            Text("Tap the button below to add text from your clipboard, or copy text on your connected Mac.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            #else
            Text("Copy some text to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
            #endif
            
            Spacer()
            Spacer()
        }
    }
    
    private var clipboardListView: some View {
        #if os(iOS)
        List {
            ForEach(store.items) { item in
                ClipboardItemCell(item: item, isCopied: copiedItemId == item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyToClipboard(item)
                        showCopiedFeedback(for: item.id)
                    }
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
        .refreshable {
            NetworkService.shared.requestSync()
            appState.addFromClipboard()
        }
        #else
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.items) { item in
                    ClipboardItemRow(item: item, isCopied: copiedItemId == item.id)
                        .onTapGesture {
                            copyToClipboard(item)
                            showCopiedFeedback(for: item.id)
                        }
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        #endif
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        #else
        UIPasteboard.general.string = item.content
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
    
    private func showCopiedFeedback(for itemId: UUID) {
        withAnimation(.spring(response: 0.3)) {
            copiedItemId = itemId
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.3)) {
                    copiedItemId = nil
                }
            }
        }
    }
    
    #if os(iOS)
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            store.removeItem(at: index)
        }
    }
    #endif
}

// MARK: - Clipboard Item Views

struct ClipboardItemCell: View {
    let item: ClipboardItem
    var isCopied: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.preview)
                .font(.body)
                .lineLimit(3)
            
            HStack(spacing: 8) {
                deviceIcon
                    .foregroundColor(deviceColor)
                    .font(.caption)
                
                Text(item.sourceDevice)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(item.formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Copied")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            isCopied ? Color.green.opacity(0.15) : Color.clear
        )
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
    
    private var deviceIcon: Image {
        if item.sourceDevice.contains("iPhone") {
            return Image(systemName: "iphone")
        } else if item.sourceDevice.contains("iPad") {
            return Image(systemName: "ipad")
        } else {
            return Image(systemName: "laptopcomputer")
        }
    }
    
    private var deviceColor: Color {
        if item.sourceDevice.contains("iPhone") || item.sourceDevice.contains("iPad") {
            return .blue
        } else {
            return .purple
        }
    }
}

#if os(macOS)
struct ClipboardItemRow: View {
    let item: ClipboardItem
    var isCopied: Bool = false
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            deviceIcon
                .foregroundColor(item.sourceDevice.contains("iPhone") || item.sourceDevice.contains("iPad") ? .blue : .purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Text(item.sourceDevice)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isCopied {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Copied")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            
            if isHovered {
                Button(action: {
                    ClipboardStore.shared.removeItem(id: item.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? (isCopied ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.1)) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var deviceIcon: some View {
        Group {
            if item.sourceDevice.contains("iPhone") {
                Image(systemName: "iphone")
            } else if item.sourceDevice.contains("iPad") {
                Image(systemName: "ipad")
            } else {
                Image(systemName: "laptopcomputer")
            }
        }
        .font(.system(size: 14))
    }
}
#endif

// MARK: - Menu Bar View (macOS only)

#if os(macOS)
struct MenuBarView: View {
    var body: some View {
        ContentView()
    }
}
#endif

#Preview {
    #if os(iOS)
    ContentView()
        .environmentObject(AppState())
    #else
    ContentView()
    #endif
}
