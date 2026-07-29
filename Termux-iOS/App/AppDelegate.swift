//
//  AppDelegate.swift
//  Termux-iOS
//
//  Performs an idempotent first-launch bootstrap for a palera1n rootless
//  device.  Only missing files are installed so user package/config changes
//  are not overwritten on subsequent launches.
//
import UIKit

public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NSLog("[Termux-iOS] launching (pacman-only /var/jb mode)")
        bootstrapRootlessFilesystem()
        IPCManager.shared.startMonitoring()
        return true
    }

    private func bootstrapRootlessFilesystem() {
        let fileManager = FileManager.default
        let root = "/var/jb"
        let targetRoot = fileManager.fileExists(atPath: root) ? root :
            (NSHomeDirectory() as NSString).appendingPathComponent(".termux-ios-root")

        do {
            try fileManager.createDirectory(atPath: targetRoot, withIntermediateDirectories: true)
            try installMissingBundleFiles(into: targetRoot, fileManager: fileManager)
        } catch {
            NSLog("[Termux-iOS] bootstrap failed: %@", String(describing: error))
        }

        // The shared parser is intentionally initialized after bootstrap so it
        // reads the device's real ~/.termux/termux.properties on first launch.
        if !fileManager.fileExists(atPath: TermuxProperties.shared.propertiesFilePath()) {
            TermuxProperties.shared.save()
        }
    }

    private func installMissingBundleFiles(into root: String, fileManager: FileManager) throws {
        let etc = (root as NSString).appendingPathComponent("etc")
        let pacmanD = (etc as NSString).appendingPathComponent("pacman.d")
        let bin = (root as NSString).appendingPathComponent("usr/bin")
        let sbin = (root as NSString).appendingPathComponent("usr/sbin")
        let localBin = (root as NSString).appendingPathComponent("usr/local/bin")
        let mobileTermux = (root as NSString).appendingPathComponent("var/mobile/.termux")
        let rootTermux = (root as NSString).appendingPathComponent("root/.termux")

        for directory in [etc, pacmanD, bin, sbin, localBin, mobileTermux, rootTermux] {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        // These are the three files that define the package-manager setup.
        copyIfMissing(source: bundleFile("pacman.conf"), destination: (etc as NSString).appendingPathComponent("pacman.conf"), fileManager: fileManager, permissions: 0o644)
        copyIfMissing(source: bundleFile("mirrorlist"), destination: (pacmanD as NSString).appendingPathComponent("mirrorlist"), fileManager: fileManager, permissions: 0o644)

        // Shell tools and native helpers are installed into the rootless PATH.
        let rootfsTools = ["pkg", "apt", "apt-get", "jb-chroot"]
        for tool in rootfsTools {
            copyIfMissing(source: bundleFile(tool), destination: (bin as NSString).appendingPathComponent(tool), fileManager: fileManager, permissions: 0o755)
        }

        // The build script places auxiliary commands and optional native
        // binaries in these directories. Copy every bundled file without
        // overwriting local versions; a supplied pacman binary is therefore
        // installed too, without inventing or replacing one on-device.
        let bundledBinaryDirectories: [(String, String)] = [
            ("termux-tools", bin),
            ("rootfs-bootstrap/usr/bin", bin),
            ("rootfs-bootstrap/usr/sbin", sbin),
            ("rootfs-bootstrap/usr/local/bin", localBin)
        ]
        for (directoryName, destinationDirectory) in bundledBinaryDirectories {
            guard let directory = bundleDirectory(directoryName),
                  let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries {
                let source = (directory as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: source, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                copyIfMissing(source: source, destination: (destinationDirectory as NSString).appendingPathComponent(entry), fileManager: fileManager, permissions: 0o755)
            }
        }

        // Keep root's properties in sync only if it has no file yet.
        copyIfMissing(source: (mobileTermux as NSString).appendingPathComponent("termux.properties"),
                      destination: (rootTermux as NSString).appendingPathComponent("termux.properties"),
                      fileManager: fileManager, permissions: 0o644)
    }

    private func bundleDirectory(_ relativePath: String) -> String? {
        let direct = Bundle.main.bundleURL.appendingPathComponent(relativePath).path
        return FileManager.default.fileExists(atPath: direct) ? direct : nil
    }

    private func bundleFile(_ name: String) -> String? {
        if let direct = Bundle.main.path(forResource: name, ofType: nil) { return direct }
        for relative in ["rootfs-bootstrap/\(name)", "rootfs-bootstrap/usr/bin/\(name)", "termux-tools/\(name)"] {
            let path = Bundle.main.bundleURL.appendingPathComponent(relative).path
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func copyIfMissing(source: String?, destination: String, fileManager: FileManager, permissions: Int) {
        guard let source = source, !fileManager.fileExists(atPath: destination), fileManager.fileExists(atPath: source) else { return }
        do {
            try fileManager.copyItem(atPath: source, toPath: destination)
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination)
        } catch {
            NSLog("[Termux-iOS] could not install %@: %@", destination, String(describing: error))
        }
    }
}
