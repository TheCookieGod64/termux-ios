//
//  AppDelegate.swift
//  JITAllower
//
//  Application Lifecycle and automatic /var/jb helper installation.
//

import UIKit

public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("[JITAllower] Launching JITAllower on iPhone 8 (palera1n rootless / TrollStore)...")
        
        setupFileSystemAndHelper()
        return true
    }
    
    private func setupFileSystemAndHelper() {
        let jbRoot = "/var/jb"
        if FileManager.default.fileExists(atPath: jbRoot) {
            print("[JITAllower] [+] Detected palera1n rootless filesystem at /var/jb")
            let binDir = (jbRoot as NSString).appendingPathComponent("usr/bin")
            try? FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true, attributes: nil)
            
            if let bundleHelper = Bundle.main.path(forResource: "jit-helper", ofType: nil) {
                let dest = (binDir as NSString).appendingPathComponent("jit-helper")
                if !FileManager.default.fileExists(atPath: dest) {
                    try? FileManager.default.copyItem(atPath: bundleHelper, toPath: dest)
                    let attrs = [FileAttributeKey.posixPermissions: 0o755]
                    try? FileManager.default.setAttributes(attrs, ofItemAtPath: dest)
                }
            }
        } else {
            print("[JITAllower] [!] Running in standard sandbox mode (host/test mode).")
        }
    }
}
