//
//  DefaultConfig.swift
//  Termux-iOS
//
//  Default configuration values and color palettes for Termux-iOS.
//  Target: iPhone 8 (iOS 15/16) | palera1n | TrollStore | pacman
//

import Foundation

public struct DefaultConfig {
    public static let defaultExtraKeys: [[String]] = [
        ["ESC", "TAB", "CTRL", "ALT", "-", "/", "|", "UP", "DOWN", "LEFT", "RIGHT", "HOME", "END", "PGUP", "PGDN"]
    ]
    
    public static let defaultFontSize: CGFloat = 13.0
    public static let minFontSize: CGFloat = 8.0
    public static let maxFontSize: CGFloat = 32.0
    
    public static let defaultJBRoot = "/var/jb"
    public static let defaultShell = "/bin/bash"
    public static let defaultRootlessShell = "/var/jb/usr/bin/bash"
    public static let defaultPackageManager = "pacman"
}

public struct TermuxTheme: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let backgroundHex: String
    public let foregroundHex: String
    public let cursorHex: String
    public let ansiColorsHex: [String]
    
    public static let termuxDark = TermuxTheme(
        id: "termux.dark",
        name: "Termux Dark (Default)",
        backgroundHex: "#000000",
        foregroundHex: "#FFFFFF",
        cursorHex: "#00FF00",
        ansiColorsHex: [
            "#000000", "#CD0000", "#00CD00", "#CDCD00", "#0000EE", "#CD00CD", "#00CDCD", "#E5E5E5",
            "#7F7F7F", "#FF0000", "#00FF00", "#FFFF00", "#5C5CFF", "#FF00FF", "#00FFFF", "#FFFFFF"
        ]
    )
    
    public static let solarizedDark = TermuxTheme(
        id: "solarized.dark",
        name: "Solarized Dark",
        backgroundHex: "#002B36",
        foregroundHex: "#839496",
        cursorHex: "#2AA198",
        ansiColorsHex: [
            "#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
            "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"
        ]
    )
    
    public static let dracula = TermuxTheme(
        id: "dracula",
        name: "Dracula",
        backgroundHex: "#282A36",
        foregroundHex: "#F8F8F2",
        cursorHex: "#FF79C6",
        ansiColorsHex: [
            "#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
            "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"
        ]
    )
    
    public static let monokai = TermuxTheme(
        id: "monokai",
        name: "Monokai",
        backgroundHex: "#272822",
        foregroundHex: "#F8F8F2",
        cursorHex: "#F92672",
        ansiColorsHex: [
            "#272822", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F8F8F2",
            "#75715E", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F9F8F5"
        ]
    )
    
    public static let allThemes: [TermuxTheme] = [
        .termuxDark,
        .solarizedDark,
        .dracula,
        .monokai
    ]
}
