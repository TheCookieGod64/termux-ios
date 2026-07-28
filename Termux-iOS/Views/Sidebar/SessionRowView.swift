//
//  SessionRowView.swift
//  Termux-iOS
//
//  Row view for an active terminal session in the left drawer navigation.
//

import SwiftUI

public struct SessionRowView: View {
    @ObservedObject public var session: TerminalSession
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onClose: () -> Void
    
    public init(session: TerminalSession, isSelected: Bool, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
    }
    
    public var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(session.title)
                        .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .gray)
                        .lineLimit(1)
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray.opacity(0.7))
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
        .cornerRadius(8)
    }
}
