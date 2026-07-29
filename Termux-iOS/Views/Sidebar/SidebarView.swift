//
//  SidebarView.swift
//  Termux-iOS
//
//  Termux-style Left Navigation Drawer (Sessions, New Session, Settings, Keyboard Toggle).
//

import SwiftUI

public struct SidebarView: View {
    @Binding public var sessions: [TerminalSession]
    @Binding public var selectedSessionID: UUID?
    @Binding public var isSidebarOpen: Bool
    @ObservedObject public var props = TermuxProperties.shared
    public var onNewSession: () -> Void
    public var onOpenSettings: () -> Void
    public var onToggleKeyboard: () -> Void
    
    public init(sessions: Binding<[TerminalSession]>,
                selectedSessionID: Binding<UUID?>,
                isSidebarOpen: Binding<Bool>,
                onNewSession: @escaping () -> Void,
                onOpenSettings: @escaping () -> Void,
                onToggleKeyboard: @escaping () -> Void) {
        self._sessions = sessions
        self._selectedSessionID = selectedSessionID
        self._isSidebarOpen = isSidebarOpen
        self.onNewSession = onNewSession
        self.onOpenSettings = onOpenSettings
        self.onToggleKeyboard = onToggleKeyboard
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Termux-iOS Header
            VStack(alignment: .leading, spacing: 4) {
                Text("TERMUX")
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                
                Text("iPhone 8 • palera1n • pacman")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Sessions List
            Text("SESSIONS (\(sessions.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 16)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            isSelected: session.id == selectedSessionID,
                            onSelect: {
                                selectedSessionID = session.id
                                withAnimation {
                                    isSidebarOpen = false
                                }
                            },
                            onClose: {
                                closeSession(session)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Action Buttons
            VStack(spacing: 8) {
                Button(action: {
                    onNewSession()
                    withAnimation {
                        isSidebarOpen = false
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.square.fill")
                        Text("New Session")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(8)
                }
                
                Button(action: {
                    onToggleKeyboard()
                }) {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("Toggle Keyboard")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundColor(.gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Menu {
                    ForEach(TermuxTheme.allThemes) { theme in
                        Button {
                            props.currentTheme = theme
                            props.save()
                        } label: {
                            HStack {
                                Text(theme.name)
                                if props.currentTheme == theme { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                        Text("Theme: \(props.currentTheme.name)")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Button(action: {
                    onOpenSettings()
                    withAnimation {
                        isSidebarOpen = false
                    }
                }) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundColor(.gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .frame(width: 260)
        .background(Color(hex: "#161618").edgesIgnoringSafeArea(.all))
    }
    
    private func closeSession(_ session: TerminalSession) {
        session.terminate()
        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
    }
}
