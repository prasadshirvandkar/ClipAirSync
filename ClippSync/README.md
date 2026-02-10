# ClipSync

A cross-device clipboard sync app for macOS and iOS using a single multiplatform target.

## Features

- **macOS Menu Bar App**: Lives in your menu bar and monitors clipboard changes
- **iOS Companion App**: Manually add clipboard items or receive them from Mac
- **Local Network Sync**: Syncs over WiFi using Bonjour - no cloud required
- **50 Item History**: Stores your last 50 copied text items

## Quick Setup

You have a multiplatform Xcode project already. Just add these files:

### Step 1: Delete default files

Delete the default `ClipSyncApp.swift` and `ContentView.swift` that Xcode created.

### Step 2: Add these files to your project

Drag these files from this folder into Xcode (ensure "Copy items if needed" is checked):

**Main files** (add to ClipSync target):

- `ClipSyncApp.swift` - App entry point
- `ContentView.swift` - Main UI

**Services** (from `Shared/Services/`, add to ClipSync target):

- `ClipboardStore.swift` - History management
- `BonjourService.swift` - Device discovery
- `NetworkService.swift` - Sync protocol
- `ClipboardMonitor.swift` - Clipboard polling (macOS)

**Models** (from `Shared/Models/`, add to ClipSync target):

- `ClipboardItem.swift` - Data model

### Step 3: Add Info.plist entries

Go to your target's **Info** tab and add:

| Key                              | Type   | Value                                                                          |
| -------------------------------- | ------ | ------------------------------------------------------------------------------ |
| `NSLocalNetworkUsageDescription` | String | ClipSync needs local network access to sync clipboard with your other devices. |
| `NSBonjourServices`              | Array  | Item 0: `_clipsync._tcp`                                                       |

For **macOS only**, also add:
| Key | Type | Value |
|-----|------|-------|
| `LSUIElement` | Boolean | YES |

### Step 4: Add Capabilities (macOS)

Go to **Signing & Capabilities** tab for the macOS destination:

1. Click **+ Capability**
2. Add **App Sandbox**
3. Check **Outgoing Connections (Client)** and **Incoming Connections (Server)**

### Step 5: Build and Run

- Select **My Mac** as destination and run - you'll see the menu bar icon
- Select an **iPhone/iPad** simulator and run - you'll see the iOS app

## File Structure

```
ClipSync/
├── ClipSyncApp.swift          # Unified app entry (macOS: menu bar, iOS: standard)
├── ContentView.swift          # Unified UI with platform conditionals
└── Shared/
    ├── Models/
    │   └── ClipboardItem.swift
    └── Services/
        ├── ClipboardStore.swift
        ├── BonjourService.swift
        ├── NetworkService.swift
        └── ClipboardMonitor.swift
```

## How It Works

- **macOS**: ClipboardMonitor polls the system clipboard every 0.5s
- **iOS**: User taps "Add from Clipboard" to capture current clipboard
- **Sync**: Bonjour discovers devices, TCP connection syncs clipboard items

## Troubleshooting

**Menu bar icon doesn't appear (macOS)**

- Ensure `LSUIElement` is set to `YES` in Info.plist
- Try cleaning build folder (Cmd+Shift+K) and rebuilding

**Devices not finding each other**

- Both must be on the same WiFi network
- Check that Bonjour services are configured in Info.plist
- Grant local network permission when prompted on iOS
