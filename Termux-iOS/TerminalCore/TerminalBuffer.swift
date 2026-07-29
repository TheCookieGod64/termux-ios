//
//  TerminalBuffer.swift
//  Termux-iOS
//
//  Terminal Screen & Scrollback Buffer for Termux-iOS.
//

import Foundation

public struct TerminalChar: Equatable {
    public var character: Character
    public var foregroundColorIndex: Int
    public var backgroundColorIndex: Int
    public var isBold: Bool
    public var isUnderline: Bool
    
    public static var blank: TerminalChar {
        return TerminalChar(character: " ", foregroundColorIndex: 7, backgroundColorIndex: 0, isBold: false, isUnderline: false)
    }
}

public class TerminalBuffer {
    public var columns: Int
    public var rows: Int
    public var cursorRow: Int = 0
    public var cursorCol: Int = 0
    
    public var screen: [[TerminalChar]]
    public var scrollback: [[TerminalChar]] = []
    public let maxScrollback: Int = 2000
    
    public var currentFg: Int = 7
    public var currentBg: Int = 0
    public var isBold: Bool = false
    public var isUnderline: Bool = false
    
    public init(columns: Int = 80, rows: Int = 24) {
        self.columns = columns
        self.rows = rows
        self.screen = Array(repeating: Array(repeating: TerminalChar.blank, count: columns), count: rows)
    }
    
    public func resize(columns newCols: Int, rows newRows: Int) {
        guard newCols > 0 && newRows > 0 else { return }
        var newScreen = Array(repeating: Array(repeating: TerminalChar.blank, count: newCols), count: newRows)
        let minRows = min(rows, newRows)
        let minCols = min(columns, newCols)
        for r in 0..<minRows {
            for c in 0..<minCols {
                newScreen[r][c] = screen[r][c]
            }
        }
        self.screen = newScreen
        self.columns = newCols
        self.rows = newRows
        if cursorRow >= newRows { cursorRow = newRows - 1 }
        if cursorCol >= newCols { cursorCol = newCols - 1 }
    }
    
    public func putCharacter(_ ch: Character) {
        if cursorRow >= rows {
            scrollUp()
            cursorRow = rows - 1
        }
        if cursorCol >= columns {
            cursorCol = 0
            cursorRow += 1
            if cursorRow >= rows {
                scrollUp()
                cursorRow = rows - 1
            }
        }
        
        let cell = TerminalChar(
            character: ch,
            foregroundColorIndex: currentFg,
            backgroundColorIndex: currentBg,
            isBold: isBold,
            isUnderline: isUnderline
        )
        screen[cursorRow][cursorCol] = cell
        cursorCol += 1
    }
    
    public func newLine() {
        cursorCol = 0
        cursorRow += 1
        if cursorRow >= rows {
            scrollUp()
            cursorRow = rows - 1
        }
    }
    
    public func carriageReturn() {
        cursorCol = 0
    }
    
    public func backspace() {
        if cursorCol > 0 {
            cursorCol -= 1
        }
    }
    
    public func clearScreen() {
        screen = Array(repeating: Array(repeating: TerminalChar.blank, count: columns), count: rows)
        cursorRow = 0
        cursorCol = 0
    }
    
    public func clearLine() {
        if cursorRow < rows {
            screen[cursorRow] = Array(repeating: TerminalChar.blank, count: columns)
        }
    }
    
    public func clearToEndOfLine() {
        if cursorRow < rows {
            for c in cursorCol..<columns {
                screen[cursorRow][c] = TerminalChar.blank
            }
        }
    }
    
    private func scrollUp() {
        if !screen.isEmpty {
            scrollback.append(screen.removeFirst())
            if scrollback.count > maxScrollback {
                scrollback.removeFirst()
            }
            screen.append(Array(repeating: TerminalChar.blank, count: columns))
        }
    }
    
    public func stringRepresentation() -> String {
        return screen.map { row in
            String(row.map { $0.character })
        }.joined(separator: "\n")
    }
}
