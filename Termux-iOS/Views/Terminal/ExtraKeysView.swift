//
//  ExtraKeysView.swift
//  Termux-iOS
//
//  Authentic Termux Extra Keys Bar above the iOS on-screen keyboard.
//  Supports ESC, TAB, CTRL, ALT, Arrow keys, and custom termux.properties keys.
//

import SwiftUI

public struct ExtraKeysView: View {
    @ObservedObject public var session: TerminalSession
    @ObservedObject public var props = TermuxProperties.shared
    public var onToggleKeyboard: () -> Void
    
    public init(session: TerminalSession, onToggleKeyboard: @escaping () -> Void = {}) {
        self.session = session
        self.onToggleKeyboard = onToggleKeyboard
    }
    
    public var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<props.extraKeys.count, id: \.self) { rowIndex in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(props.extraKeys[rowIndex], id: \.self) { key in
                            ExtraKeyButton(
                                title: key,
                                isActive: (key.uppercased() == "CTRL" && session.ctrlActive) || (key.uppercased() == "ALT" && session.altActive)
                            ) {
                                session.handleExtraKey(key)
                            }
                        }
                        
                        // Keyboard toggle button on the right edge
                        if rowIndex == 0 {
                            Button(action: onToggleKeyboard) {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(hex: props.currentTheme.foregroundHex))
                                    .frame(width: 42, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: "#444444").opacity(0.85))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
            }
        }
        .background(Color(hex: props.currentTheme.backgroundHex).opacity(0.95))
        .border(Color.gray.opacity(0.3), width: 0.5)
    }
}
