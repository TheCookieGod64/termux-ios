//
//  TerminalSession.swift
//  Termux-iOS
//
//  Observable Terminal Session manager (PTY, VT100 Parser, Buffer, Input).
//

import Foundation
import Combine
import SwiftUI

public class TerminalSession: ObservableObject, Identifiable, Equatable {
    public let id = UUID()
    @Published public var title: String
    @Published public var isRunning: Bool = false
    @Published public var buffer: TerminalBuffer
    @Published public var refreshCounter: Int = 0
    
    public var pty: PTYProcess
    private var parser: VT100Parser
    
    public var ctrlActive: Bool = false
    public var altActive: Bool = false
    
    public static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        return lhs.id == rhs.id
    }
    
    public init(title: String = "bash", columns: Int = 80, rows: Int = 24) {
        self.title = title
        let buf = TerminalBuffer(columns: columns, rows: rows)
        self.buffer = buf
        self.parser = VT100Parser(buffer: buf)
        self.pty = PTYProcess()
        
        setupPTYHandlers()
    }
    
    private func setupPTYHandlers() {
        pty.onDataReceived = { [weak self] data in
            guard let self = self else { return }
            self.parser.feed(data)
            self.refreshCounter += 1
        }
        
        pty.onProcessTerminated = { [weak self] status in
            guard let self = self else { return }
            self.isRunning = false
            self.parser.feed("\r\n[Process completed (status \(status))]\r\n")
            self.refreshCounter += 1
        }
    }
    
    public func start(columns: Int = 80, rows: Int = 24) {
        buffer.resize(columns: columns, rows: rows)
        if pty.start(columns: columns, rows: rows) {
            isRunning = true
            // Display welcome banner
            parser.feed("\u{1b}[1;36m================================================\r\n")
            parser.feed(" Welcome to Termux-iOS (iPhone 8 | palera1n)\r\n")
            parser.feed(" Rootfs: /var/jb | Package Manager: PACMAN\r\n")
            parser.feed("================================================\u{1b}[0m\r\n")
            refreshCounter += 1
        } else {
            parser.feed("\r\n[Error: Failed to spawn shell in /var/jb]\r\n")
            refreshCounter += 1
        }
    }
    
    public func setSize(columns: Int, rows: Int) {
        guard columns > 0 && rows > 0 else { return }
        buffer.resize(columns: columns, rows: rows)
        pty.setWindowSize(columns: columns, rows: rows)
        refreshCounter += 1
    }
    
    public func handleInputString(_ string: String) {
        guard isRunning else { return }
        var toSend = string
        
        if ctrlActive {
            if let first = string.uppercased().first, let ascii = first.asciiValue, ascii >= 64 && ascii <= 95 {
                let ctrlChar = Character(UnicodeScalar(ascii - 64))
                toSend = String(ctrlChar)
            }
            ctrlActive = false
        } else if altActive {
            toSend = "\u{1b}" + string
            altActive = false
        }
        
        pty.writeString(toSend)
    }
    
    public func handleExtraKey(_ key: String) {
        switch key.uppercased() {
        case "ESC":
            pty.writeString("\u{1b}")
        case "TAB":
            pty.writeString("\t")
        case "CTRL":
            ctrlActive.toggle()
            refreshCounter += 1
        case "ALT":
            altActive.toggle()
            refreshCounter += 1
        case "UP":
            pty.writeString("\u{1b}[A")
        case "DOWN":
            pty.writeString("\u{1b}[B")
        case "RIGHT":
            pty.writeString("\u{1b}[C")
        case "LEFT":
            pty.writeString("\u{1b}[D")
        case "HOME":
            pty.writeString("\u{1b}[H")
        case "END":
            pty.writeString("\u{1b}[F")
        case "PGUP":
            pty.writeString("\u{1b}[5~")
        case "PGDN":
            pty.writeString("\u{1b}[6~")
        case "-", "/", "|", "~", "_", "=", "+", "*", "&", "^", "%", "$", "#", "@", "!":
            handleInputString(key)
        default:
            handleInputString(key)
        }
    }
    
    public func terminate() {
        pty.terminate()
        isRunning = false
    }
}
