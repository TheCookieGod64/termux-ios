//
//  TerminalView.swift
//  Termux-iOS
//
//  VT100 Terminal SwiftUI View with touch gestures, extra keys, and pinch-to-zoom.
//

import SwiftUI
import UIKit

public struct TerminalView: View {
    @ObservedObject public var session: TerminalSession
    @ObservedObject public var props = TermuxProperties.shared
    @State private var isKeyboardVisible: Bool = true
    @State private var showingContextMenu: Bool = false
    @State private var currentZoom: CGFloat = 1.0
    
    public init(session: TerminalSession) {
        self.session = session
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: props.currentTheme.backgroundHex)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Terminal Display Area
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        let lines = renderLines()
                        ForEach(0..<lines.count, id: \.self) { rowIdx in
                            HStack(spacing: 0) {
                                Text(lines[rowIdx])
                                    .font(.system(size: props.fontSize * currentZoom, weight: .regular, design: .monospaced))
                                    .foregroundColor(Color(hex: props.currentTheme.foregroundHex))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: (props.fontSize * currentZoom) * 1.2, alignment: .leading)
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
                    isKeyboardVisible.toggle()
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
                
                // Extra Keys Toolbar
                if isKeyboardVisible {
                    ExtraKeysView(session: session) {
                        withAnimation {
                            isKeyboardVisible.toggle()
                        }
                    }
                }
            }
        }
    }
    
    private func renderLines() -> [String] {
        return session.buffer.screen.map { row in
            String(row.map { $0.character })
        }
    }
}
