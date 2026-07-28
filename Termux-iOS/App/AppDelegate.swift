//
//  AppDelegate.swift
//  Termux-iOS
//
//  Application Lifecycle, /var/jb filesystem check, and Pacman bootstrap initialization.
//

import UIKit

public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("[Termux-iOS] Launching Termux for iPhone 8 (palera1n rootless / TrollStore)...")
        
        setupFileSystem()
        IPCManager.shared.startMonitoring()
        
        return true
    }
    
    private func setupFileSystem() {
        let jbRoot = "/var/jb"
        if FileManager.default.fileExists(atPath: jbRoot) {
            print("[Termux-iOS] [+] Found palera1n rootless filesystem at /var/jb")
            let termuxDir = "/var/jb/var/mobile/.termux"
            try? FileManager.default.createDirectory(atPath: termuxDir, withIntermediateDirectories: true, attributes: nil)
        } else {
            print("[Termux-iOS] [!] /var/jb not found on current filesystem. Running in standalone sandbox mode.")
            let localTermux = (NSHomeDirectory() as NSString).appendingPathComponent(".termux")
            try? FileManager.default.createDirectory(atPath: localTermux, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Save initial termux.properties if not present
        if !FileManager.default.fileExists(atPath: TermuxProperties.shared.propertiesFilePath()) {
            TermuxProperties.shared.save()
        }
    }
}
