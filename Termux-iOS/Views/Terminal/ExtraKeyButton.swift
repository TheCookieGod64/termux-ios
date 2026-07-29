//
//  ExtraKeyButton.swift
//  Termux-iOS
//
//  Individual Extra Key Button component for Termux keyboard bar.
//

import SwiftUI

public struct ExtraKeyButton: View {
    public let title: String
    public let isActive: Bool
    public let action: () -> Void
    
    @ObservedObject private var props = TermuxProperties.shared
    
    public init(title: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isActive = isActive
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? Color(hex: props.currentTheme.backgroundHex) : Color(hex: props.currentTheme.foregroundHex))
                .frame(minWidth: 42, minHeight: 36)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color(hex: props.currentTheme.cursorHex) : Color(hex: props.currentTheme.ansiColorsHex.count > 8 ? props.currentTheme.ansiColorsHex[8] : "#333333").opacity(0.85))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
