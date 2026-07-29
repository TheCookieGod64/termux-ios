//
//  TerminalView.swift
//  Termux-iOS
//
//  VT100 Terminal SwiftUI View with interactive iOS keyboard input, cursor rendering, and Extra Keys.
//

import SwiftUI
import UIKit

public struct TerminalView: View {
    @ObservedObject public var session: TerminalSession
    @ObservedObject public var props = TermuxProperties.shared
    @Binding public var isKeyboardVisible: Bool
    @State private var showingContextMenu: Bool = false
    @State private var currentZoom: CGFloat = 1.0
    @State private var cursorVisible: Bool = true
    
    public init(session: TerminalSession, isKeyboardVisible: Binding<Bool>) {
        self.session = session
        self._isKeyboardVisible = isKeyboardVisible
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: props.currentTheme.backgroundHex)
                .edgesIgnoringSafeArea(.all)
            
            // Hidden UIKit Keyboard Bridge (UIKeyInput)
            TerminalKeyboardRepresentable(session: session, isKeyboardVisible: $isKeyboardVisible)
                .frame(width: 1, height: 1)
                .opacity(0.01)
            
            VStack(spacing: 0) {
                // Terminal Display Area
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        let lines = renderLinesWithCursor()
                        ForEach(0..<lines.count, id: \.self) { rowIdx in
                            HStack(spacing: 0) {
                                let lineText = lines[rowIdx]
                                let isCursorRow = (rowIdx == session.buffer.cursorRow)
                                
                                if isCursorRow && cursorVisible {
                                    renderCursorLine(rowText: lineText, cursorCol: session.buffer.cursorCol)
                                } else {
                                    Text(lineText)
                                        .font(.system(size: props.fontSize * currentZoom, weight: .regular, design: .monospaced))
                                        .foregroundColor(Color(hex: props.currentTheme.foregroundHex))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(height: (props.fontSize * currentZoom) * 1.25, alignment: .leading)
                        }
                    }
                    .padding(6)
                    .id(session.refreshCounter)
                }
                .background(Color(hex: props.currentTheme.backgroundHex))
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let scale = value
                            if scale > 0.5 && scale < 3.0 {
                                self.currentZoom = scale
                            }
                        }
                        .onEnded { value in
                            let newSize = props.fontSize * value
                            props.fontSize = min(max(newSize, DefaultConfig.minFontSize), DefaultConfig.maxFontSize)
                            self.currentZoom = 1.0
                        }
                )
                .onTapGesture {
                    isKeyboardVisible = true
                }
                .onLongPressGesture {
                    showingContextMenu = true
                }
                .contextMenu {
                    Button(action: {
                        if let text = UIPasteboard.general.string {
                            session.handleInputString(text)
                        }
                    }) {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    
                    Button(action: {
                        UIPasteboard.general.string = session.buffer.stringRepresentation()
                    }) {
                        Label("Copy Screen Buffer", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: {
                        session.buffer.clearScreen()
                        session.refreshCounter += 1
                    }) {
                        Label("Reset Terminal", systemImage: "arrow.counterclockwise")
                    }
                    
                    Button(role: .destructive, action: {
                        session.terminate()
                    }) {
                        Label("Kill Session", systemImage: "xmark.octagon")
                    }
                }
                
                // Extra Keys Toolbar above the iOS on-screen keyboard
                if isKeyboardVisible {
                    ExtraKeysView(session: session) {
                        withAnimation {
                            isKeyboardVisible.toggle()
                        }
                    }
                }
            }
        }
        .onAppear {
            startCursorTimer()
        }
    }
    
    @ViewBuilder
    private func renderCursorLine(rowText: String, cursorCol: Int) -> some View {
        let col = min(max(0, cursorCol), rowText.count)
        let cursorIndex = rowText.index(rowText.startIndex, offsetBy: col)
        let prefixText = String(rowText[..<cursorIndex])
        let suffixText = String(rowText[cursorIndex...])
        let cursorText = suffixText.isEmpty ? " " : String(suffixText.prefix(1))
        let remainder = suffixText.isEmpty ? "" : String(suffixText.dropFirst())
        let foreground = Color(hex: props.currentTheme.foregroundHex)
        let cursorColor = Color(hex: props.currentTheme.cursorHex)

        HStack(spacing: 0) {
            Text(prefixText)
                .font(.system(size: props.fontSize * currentZoom, design: .monospaced))
                .foregroundColor(foreground)

            Group {
                switch props.cursorStyle {
                case .block:
                    Text(cursorText)
                        .font(.system(size: props.fontSize * currentZoom, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: props.currentTheme.backgroundHex))
                        .background(cursorColor)
                case .underline:
                    Text(cursorText)
                        .font(.system(size: props.fontSize * currentZoom, design: .monospaced))
                        .foregroundColor(foreground)
                        .overlay(Rectangle().fill(cursorColor).frame(height: 2), alignment: .bottom)
                case .bar:
                    Text(cursorText)
                        .font(.system(size: props.fontSize * currentZoom, design: .monospaced))
                        .foregroundColor(foreground)
                        .overlay(Rectangle().fill(cursorColor).frame(width: 2), alignment: .leading)
                }
            }

            Text(remainder)
                .font(.system(size: props.fontSize * currentZoom, design: .monospaced))
                .foregroundColor(foreground)
        }
    }
    
    private func renderLinesWithCursor() -> [String] {
        return session.buffer.screen.map { row in
            String(row.map { $0.character })
        }
    }
    
    private func startCursorTimer() {
        guard props.cursorBlink else {
            cursorVisible = true
            return
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                self.cursorVisible.toggle()
            }
        }
    }
}
