//
//  AppItem.swift
//  JITAllower
//
//  Represents an installed or running iOS application target for JIT enablement.
//  Supports TrollStore, App Store, and sideloaded applications.
//

import Foundation

public struct AppItem: Identifiable, Equatable {
    public let id = UUID()
    public let bundleID: String
    public let name: String
    public let pid: Int32?
    public var isJITEnabled: Bool
    public let isTrollStoreApp: Bool
    
    public init(bundleID: String, name: String, pid: Int32? = nil, isJITEnabled: Bool = false, isTrollStoreApp: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
        self.isJITEnabled = isJITEnabled
        self.isTrollStoreApp = isTrollStoreApp
    }
    
    public static let defaultTargets: [AppItem] = [
        AppItem(bundleID: "org.dolphin-emu.dolphinios", name: "DolphiniOS (Wii / GameCube)", pid: nil, isJITEnabled: false, isTrollStoreApp: false),
        AppItem(bundleID: "com.utmapp.UTM", name: "UTM Virtual Machines", pid: nil, isJITEnabled: false, isTrollStoreApp: false),
        AppItem(bundleID: "org.ppsspp.ppsspp", name: "PPSSPP (PSP Emulator)", pid: nil, isJITEnabled: false, isTrollStoreApp: false),
        AppItem(bundleID: "net.kdt.pojavlaunch", name: "PojavLauncher (Minecraft Java)", pid: nil, isJITEnabled: false, isTrollStoreApp: false),
        AppItem(bundleID: "com.libretro.RetroArch", name: "RetroArch Arcade", pid: nil, isJITEnabled: false, isTrollStoreApp: false)
    ]
}
