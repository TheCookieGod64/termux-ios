//
//  IPCManager.swift
//  Termux-iOS
//
//  Bridges CLI scripts (termux-clipboard-get/set, termux-open) with iOS UIKit.
//

import Foundation
import UIKit

public class IPCManager {
    public static let shared = IPCManager()
    
    private var timer: Timer?
    
    public init() {}
    
    public func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkOpenRequest()
            self?.syncClipboard()
        }
    }
    
    private func termuxDir() -> String {
        let jbDir = "/var/jb/var/mobile/.termux"
        let homeDir = (NSHomeDirectory() as NSString).appendingPathComponent(".termux")
        if FileManager.default.fileExists(atPath: jbDir) {
            return jbDir
        }
        return homeDir
    }
    
    private func checkOpenRequest() {
        let reqPath = (termuxDir() as NSString).appendingPathComponent(".open_request")
        guard FileManager.default.fileExists(atPath: reqPath) else { return }
        
        if let target = try? String(contentsOfFile: reqPath, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty {
            try? FileManager.default.removeItem(atPath: reqPath)
            
            DispatchQueue.main.async {
                if let url = URL(string: target) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
    }
    
    private func syncClipboard() {
        let clipPath = (termuxDir() as NSString).appendingPathComponent(".clipboard")
        guard FileManager.default.fileExists(atPath: clipPath) else { return }
        
        if let content = try? String(contentsOfFile: clipPath, encoding: .utf8) {
            DispatchQueue.main.async {
                if UIPasteboard.general.string != content {
                    UIPasteboard.general.string = content
                }
            }
        }
    }
}
