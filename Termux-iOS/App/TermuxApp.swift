//
//  TermuxApp.swift
//  Termux-iOS
//
//  @main SwiftUI entry point for Termux-iOS.
//  Target: iPhone 8 | iOS 15/16 | palera1n | TrollStore | pacman
//

import SwiftUI
import UIKit

@main
public struct TermuxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var props = TermuxProperties.shared
    @State private var sessions: [TerminalSession] = []
    @State private var selectedSessionID: UUID?
    @State private var isSidebarOpen: Bool = false
    @State private var isKeyboardVisible: Bool = true
    @State private var showingSettings: Bool = false
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                // Main Terminal Window
                if let session = activeSession() {
                    TerminalView(session: session, isKeyboardVisible: $isKeyboardVisible)
                        .edgesIgnoringSafeArea(.bottom)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Active Sessions")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Button("Start New Session") {
                            createNewSession()
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.edgesIgnoringSafeArea(.all))
                }
                
                // Top Overlay: Menu toggle button
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSidebarOpen.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .bold))
                            Text(activeSession()?.title ?? "Termux")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                
                // Sidebar Navigation Drawer Overlay
                if isSidebarOpen {
                    Color.black.opacity(0.45)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation {
                                isSidebarOpen = false
                            }
                        }
                    
                    SidebarView(
                        sessions: $sessions,
                        selectedSessionID: $selectedSessionID,
                        isSidebarOpen: $isSidebarOpen,
                        onNewSession: {
                            createNewSession()
                        },
                        onOpenSettings: {
                            showingSettings = true
                        },
                        onToggleKeyboard: {
                            isKeyboardVisible.toggle()
                        }
                    )
                    .transition(.move(edge: .leading))
                    .zIndex(10)
                }
            }
            .onAppear {
                if sessions.isEmpty {
                    createNewSession()
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            // Termux-style edge swipe: reveal the drawer from the left and
            // dismiss it with a swipe back to the edge.
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let openedFromEdge = value.startLocation.x < 44 && value.translation.width > 80
                        let closedToEdge = isSidebarOpen && value.translation.width < -80
                        if openedFromEdge || closedToEdge {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSidebarOpen = openedFromEdge
                            }
                        }
                    }
            )
        }
    }
    
    private func activeSession() -> TerminalSession? {
        if let id = selectedSessionID, let found = sessions.first(where: { $0.id == id }) {
            return found
        }
        return sessions.first
    }
    
    private func createNewSession() {
        let index = sessions.count + 1
        let newSession = TerminalSession(title: "bash [\(index)]")
        sessions.append(newSession)
        selectedSessionID = newSession.id
        newSession.start()
    }
}
