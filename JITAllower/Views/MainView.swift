//
//  MainView.swift
//  JITAllower
//
//  Main screen featuring 1 big "ALLOW JIT" button to unlock JIT across all apps.
//  Target: iPhone 8 | palera1n (/var/jb) | TrollStore
//

import SwiftUI

public struct MainView: View {
    @ObservedObject public var manager = JITManager.shared
    @State private var showingAppSelector: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color(hex: "#0F1117")
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    Text("JITALLOWER")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("iPhone 8 • palera1n (/var/jb) • TrollStore")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 40)
                
                Spacer()
                
                // 1 BIG "ALLOW JIT" BUTTON
                Button(action: {
                    showingAppSelector = true
                }) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.orange, Color.red]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 140, height: 140)
                                .shadow(color: Color.orange.opacity(0.5), radius: 20, x: 0, y: 10)
                            
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 64, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("ALLOW JIT")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Enable JIT on All Apps or Choose Specific App")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Quick 1-Tap "Enable All" Secondary Button
                Button(action: {
                    manager.enableJITForAllApps()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Instant Unlock All Apps")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(20)
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Recent Activity Log
                VStack(alignment: .leading, spacing: 6) {
                    Text("STATUS LOG")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<min(8, manager.statusLog.count), id: \.self) { idx in
                                Text(manager.statusLog[idx])
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(manager.statusLog[idx].contains("[✔]") ? .green : .white)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 110)
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingAppSelector) {
            AppSelectionView()
        }
    }
}

extension Color {
    public init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
