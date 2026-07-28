//
//  SettingsView.swift
//  Termux-iOS
//
//  Main Termux-iOS Settings View (termux.properties, Theme, Cursor, Pacman).
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var props = TermuxProperties.shared
    @Environment(\.presentationMode) private var presentationMode
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("APPEARANCE")) {
                    NavigationLink(destination: ColorSchemeView()) {
                        HStack {
                            Text("Color Scheme")
                            Spacer()
                            Text(props.currentTheme.name)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(props.fontSize)) pt")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $props.fontSize, in: DefaultConfig.minFontSize...DefaultConfig.maxFontSize, step: 1.0)
                    }
                }
                
                Section(header: Text("TERMINAL BEHAVIOR")) {
                    Picker("Cursor Style", selection: $props.cursorStyle) {
                        ForEach(CursorStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                    
                    Toggle("Cursor Blink", isOn: $props.cursorBlink)
                    
                    HStack {
                        Text("Bell Character")
                        Spacer()
                        Text(props.bellCharacter)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("PACKAGE MANAGER & ROOTFS")) {
                    NavigationLink(destination: PacmanSettingsView()) {
                        HStack {
                            Text("Pacman Configuration")
                            Spacer()
                            Text("pacman (no apt)")
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Section(header: Text("CONFIGURATION FILES")) {
                    Button(action: {
                        props.save()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save termux.properties to disk")
                        }
                    }
                    
                    Button(action: {
                        props.reload()
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Reload configuration from disk")
                        }
                    }
                }
                
                Section(header: Text("ABOUT TERMUX-IOS")) {
                    HStack {
                        Text("Target Device")
                        Spacer()
                        Text("iPhone 8 (iOS 15/16)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Jailbreak Support")
                        Spacer()
                        Text("palera1n rootless (/var/jb)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Installation Method")
                        Spacer()
                        Text("TrollStore (.tipa)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.118.0-ios (pacman-edition)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Termux Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
