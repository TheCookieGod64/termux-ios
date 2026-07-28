//
//  AppDelegate.swift
//  Termux-iOS
//
//  Application Lifecycle, automatic /var/jb rootfs bootstrap, and TrollStore preparation.
//

import UIKit

public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("[Termux-iOS] Launching Termux for iPhone 8 (palera1n rootless / TrollStore)...")
        
        setupFileSystemAndBootstrap()
        IPCManager.shared.startMonitoring()
        
        return true
    }
    
    private func setupFileSystemAndBootstrap() {
        let jbRoot = "/var/jb"
        if FileManager.default.fileExists(atPath: jbRoot) {
            print("[Termux-iOS] [+] Found palera1n rootless filesystem at /var/jb")
            let termuxDir = "/var/jb/var/mobile/.termux"
            try? FileManager.default.createDirectory(atPath: termuxDir, withIntermediateDirectories: true, attributes: nil)
            
            // Automatically install jb-chroot from app bundle if not in /var/jb/usr/bin
            bootstrapBundledTools(targetRoot: jbRoot)
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
    
    private func bootstrapBundledTools(targetRoot: String) {
        let fileMgr = FileManager.default
        let binDir = (targetRoot as NSString).appendingPathComponent("usr/bin")
        let etcDir = (targetRoot as NSString).appendingPathComponent("etc")
        
        try? fileMgr.createDirectory(atPath: binDir, withIntermediateDirectories: true, attributes: nil)
        try? fileMgr.createDirectory(atPath: etcDir, withIntermediateDirectories: true, attributes: nil)
        
        // Copy jb-chroot helper if bundled
        if let jbChrootBundlePath = Bundle.main.path(forResource: "jb-chroot", ofType: nil) {
            let dest = (binDir as NSString).appendingPathComponent("jb-chroot")
            if !fileMgr.fileExists(atPath: dest) {
                try? fileMgr.copyItem(atPath: jbChrootBundlePath, toPath: dest)
                setExecutablePermissions(path: dest)
            }
        }
        
        // Copy pkg wrapper if bundled
        if let pkgBundlePath = Bundle.main.path(forResource: "pkg", ofType: nil) {
            let dest = (binDir as NSString).appendingPathComponent("pkg")
            if !fileMgr.fileExists(atPath: dest) {
                try? fileMgr.copyItem(atPath: pkgBundlePath, toPath: dest)
                setExecutablePermissions(path: dest)
            }
        }
        
        // Copy pacman.conf if bundled and not present
        if let pacmanConfPath = Bundle.main.path(forResource: "pacman.conf", ofType: nil) {
            let dest = (etcDir as NSString).appendingPathComponent("pacman.conf")
            if !fileMgr.fileExists(atPath: dest) {
                try? fileMgr.copyItem(atPath: pacmanConfPath, toPath: dest)
            }
        }
    }
    
    private func setExecutablePermissions(path: String) {
        let attrs = [FileAttributeKey.posixPermissions: 0o755]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: path)
    }
}
