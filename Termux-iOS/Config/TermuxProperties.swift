//
//  TermuxProperties.swift
//  Termux-iOS
//
//  Parses and manages ~/.termux/termux.properties configuration.
//

import Foundation
import Combine
import SwiftUI

public enum CursorStyle: String, CaseIterable {
    case block = "block"
    case underline = "underline"
    case bar = "bar"
}

public class TermuxProperties: ObservableObject {
    public static let shared = TermuxProperties()
    
    @Published public var extraKeys: [[String]] = DefaultConfig.defaultExtraKeys
    @Published public var cursorStyle: CursorStyle = .block
    @Published public var cursorBlink: Bool = true
    @Published public var bellCharacter: String = "ignore"
    @Published public var pkgManager: String = "pacman"
    @Published public var currentTheme: TermuxTheme = .termuxDark
    @Published public var fontSize: CGFloat = DefaultConfig.defaultFontSize
    
    private var fileWatcherTimer: Timer?
    
    public init() {
        reload()
        startWatching()
    }
    
    public func configDirectoryPath() -> String {
        let jbDir = "/var/jb/var/mobile/.termux"
        let homeDir = (NSHomeDirectory() as NSString).appendingPathComponent(".termux")
        if FileManager.default.fileExists(atPath: jbDir) {
            return jbDir
        }
        return homeDir
    }
    
    public func propertiesFilePath() -> String {
        return (configDirectoryPath() as NSString).appendingPathComponent("termux.properties")
    }
    
    public func reload() {
        let path = propertiesFilePath()
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }
        
        parse(content: content)
    }
    
    public func parse(content: String) {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            
            switch key {
            case "extra-keys":
                if let parsedKeys = parseExtraKeys(from: value) {
                    DispatchQueue.main.async {
                        self.extraKeys = parsedKeys
                    }
                }
            case "cursor-style":
                if let style = CursorStyle(rawValue: value.lowercased()) {
                    DispatchQueue.main.async {
                        self.cursorStyle = style
                    }
                }
            case "cursor-blink":
                DispatchQueue.main.async {
                    self.cursorBlink = (value.lowercased() == "true" || value == "1")
                }
            case "bell-character":
                DispatchQueue.main.async {
                    self.bellCharacter = value
                }
            case "pkg-manager":
                DispatchQueue.main.async {
                    self.pkgManager = value.lowercased()
                }
            default:
                break
            }
        }
    }
    
    private func parseExtraKeys(from string: String) -> [[String]]? {
        // Simple parser for termux extra-keys syntax: [['ESC','TAB',...]]
        var cleaned = string
        cleaned = cleaned.replacingOccurrences(of: "[", with: "")
        cleaned = cleaned.replacingOccurrences(of: "]", with: "")
        cleaned = cleaned.replacingOccurrences(of: "'", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        
        let keys = cleaned.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return nil }
        return [keys]
    }
    
    public func save() {
        let dir = configDirectoryPath()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        
        var lines: [String] = []
        lines.append("# Termux-iOS Configuration File (~/.termux/termux.properties)")
        lines.append("# Target: iPhone 8 | iOS 15/16 | palera1n | TrollStore")
        lines.append("")
        
        let extraKeysStr = extraKeys.map { row in
            "[" + row.map { "'\($0)'" }.joined(separator: ",") + "]"
        }.joined(separator: ",")
        lines.append("extra-keys = [\(extraKeysStr)]")
        lines.append("cursor-style = \(cursorStyle.rawValue)")
        lines.append("cursor-blink = \(cursorBlink ? "true" : "false")")
        lines.append("bell-character = \(bellCharacter)")
        lines.append("pkg-manager = \(pkgManager)")
        
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(toFile: propertiesFilePath(), atomically: true, encoding: .utf8)
    }
    
    private func startWatching() {
        fileWatcherTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let triggerPath = (self.configDirectoryPath() as NSString).appendingPathComponent(".reload_trigger")
            if FileManager.default.fileExists(atPath: triggerPath) {
                try? FileManager.default.removeItem(atPath: triggerPath)
                self.reload()
            }
        }
    }
}
