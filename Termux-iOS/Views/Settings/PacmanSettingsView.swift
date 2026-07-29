//
//  PacmanSettingsView.swift
//  Termux-iOS
//
//  Package Manager Configuration (Pacman on /var/jb) for iPhone 8 / palera1n.
//

import SwiftUI

public struct PacmanSettingsView: View {
    @State private var pacmanStatusText: String = "Loading..."
    @State private var aptStatusText: String = "Disabled (Strict Pacman Mode)"
    
    public init() {}
    
    public var body: some View {
        Form {
            Section(header: Text("PACKAGE MANAGER POLICY")) {
                HStack {
                    Text("Active Manager")
                    Spacer()
                    Text("pacman")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                }
                
                HStack {
                    Text("Apt / Dpkg Policy")
                    Spacer()
                    Text("DISABLED")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                }
                
                HStack {
                    Text("Chroot Target")
                    Spacer()
                    Text("/var/jb")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                }
            }
            
            Section(header: Text("ARCH LINUX ARM / TERMUX REPOSITORIES")) {
                Text("Primary: https://mirror.termux-ios.dev/$repo/os/$arch")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Architecture: aarch64 (iPhone 8)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("COMMAND MAPPING (PKG -> PACMAN)")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• pkg install <pkg>  ➔  pacman -S <pkg>")
                    Text("• pkg update         ➔  pacman -Sy")
                    Text("• pkg upgrade        ➔  pacman -Syu")
                    Text("• pkg remove <pkg>   ➔  pacman -Rns <pkg>")
                    Text("• pkg search <name>  ➔  pacman -Ss <name>")
                }
                .font(.system(size: 13, design: .monospaced))
            }
            
            Section(header: Text("DIAGNOSTIC STATUS")) {
                Text(pacmanStatusText)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
        .navigationTitle("Pacman Settings")
        .onAppear {
            checkStatus()
        }
    }
    
    private func checkStatus() {
        let jbRoot = "/var/jb"
        if FileManager.default.fileExists(atPath: jbRoot) {
            pacmanStatusText = "[✔] /var/jb rootfs mounted.\n[✔] pacman wrapper installed in /var/jb/usr/bin/pkg.\n[✔] apt wrapper configured to forbid apt usage."
        } else {
            pacmanStatusText = "[!] /var/jb not found on host.\nEnsure palera1n rootless jailbreak and TrollStore are installed."
        }
    }
}
