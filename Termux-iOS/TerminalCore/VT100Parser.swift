//
//  VT100Parser.swift
//  Termux-iOS
//
//  ANSI/VT100 & Xterm-256 Escape Code State Machine Parser.
//

import Foundation

public class VT100Parser {
    public let buffer: TerminalBuffer
    private var inEscape: Bool = false
    private var inCSI: Bool = false
    private var csiParamBuffer: String = ""
    
    public init(buffer: TerminalBuffer) {
        self.buffer = buffer
    }
    
    public func feed(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return
        }
        feed(string)
    }
    
    public func feed(_ text: String) {
        for char in text {
            if inCSI {
                if char.isASCII && (char.isNumber || char == ";" || char == "?") {
                    csiParamBuffer.append(char)
                } else {
                    handleCSICommand(command: char, params: csiParamBuffer)
                    inCSI = false
                    inEscape = false
                    csiParamBuffer = ""
                }
            } else if inEscape {
                if char == "[" {
                    inCSI = true
                    csiParamBuffer = ""
                } else {
                    // Simple two-character escape code
                    inEscape = false
                }
            } else {
                switch char {
                case "\u{1b}":
                    inEscape = true
                case "\n":
                    buffer.newLine()
                case "\r":
                    buffer.carriageReturn()
                case "\u{8}", "\u{7f}":
                    buffer.backspace()
                case "\t":
                    let spaces = 8 - (buffer.cursorCol % 8)
                    for _ in 0..<spaces {
                        buffer.putCharacter(" ")
                    }
                case "\u{7}":
                    // Bell character - ignored or triggered according to properties
                    break
                default:
                    if !char.isASCII || (char >= " " && char <= "~") || char.isLetter || char.isNumber || char.isSymbol || char.isPunctuation {
                        buffer.putCharacter(char)
                    }
                }
            }
        }
    }
    
    private func handleCSICommand(command: Character, params: String) {
        let args = params.components(separatedBy: ";").compactMap { Int($0) }
        
        switch command {
        case "m": // SGR - Select Graphic Rendition (colors, bold, underline)
            if args.isEmpty || (args.count == 1 && args[0] == 0) {
                buffer.currentFg = 7
                buffer.currentBg = 0
                buffer.isBold = false
                buffer.isUnderline = false
                return
            }
            
            var index = 0
            while index < args.count {
                let code = args[index]
                switch code {
                case 0:
                    buffer.currentFg = 7
                    buffer.currentBg = 0
                    buffer.isBold = false
                    buffer.isUnderline = false
                case 1:
                    buffer.isBold = true
                case 4:
                    buffer.isUnderline = true
                case 30...37:
                    buffer.currentFg = code - 30
                case 40...47:
                    buffer.currentBg = code - 40
                case 90...97:
                    buffer.currentFg = (code - 90) + 8
                case 100...107:
                    buffer.currentBg = (code - 100) + 8
                case 38: // 256-color fg: 38;5;n
                    if index + 2 < args.count && args[index + 1] == 5 {
                        buffer.currentFg = args[index + 2]
                        index += 2
                    }
                case 48: // 256-color bg: 48;5;n
                    if index + 2 < args.count && args[index + 1] == 5 {
                        buffer.currentBg = args[index + 2]
                        index += 2
                    }
                case 39:
                    buffer.currentFg = 7
                case 49:
                    buffer.currentBg = 0
                default:
                    break
                }
                index += 1
            }
        case "A": // Cursor Up
            let n = max(1, args.first ?? 1)
            buffer.cursorRow = max(0, buffer.cursorRow - n)
        case "B": // Cursor Down
            let n = max(1, args.first ?? 1)
            buffer.cursorRow = min(buffer.rows - 1, buffer.cursorRow + n)
        case "C": // Cursor Forward
            let n = max(1, args.first ?? 1)
            buffer.cursorCol = min(buffer.columns - 1, buffer.cursorCol + n)
        case "D": // Cursor Backward
            let n = max(1, args.first ?? 1)
            buffer.cursorCol = max(0, buffer.cursorCol - n)
        case "H", "f": // Cursor Position
            let row = max(0, min(buffer.rows - 1, (args.first ?? 1) - 1))
            let col = max(0, min(buffer.columns - 1, (args.count > 1 ? args[1] : 1) - 1))
            buffer.cursorRow = row
            buffer.cursorCol = col
        case "J": // Erase Display
            let mode = args.first ?? 0
            if mode == 2 || mode == 3 {
                buffer.clearScreen()
            }
        case "K": // Erase in Line
            let mode = args.first ?? 0
            if mode == 0 {
                buffer.clearToEndOfLine()
            } else if mode == 2 {
                buffer.clearLine()
            }
        default:
            break
        }
    }
}
