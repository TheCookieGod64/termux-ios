//
//  ColorSchemeView.swift
//  Termux-iOS
//
//  Theme & Color Scheme Picker for Termux-iOS.
//

import SwiftUI

public struct ColorSchemeView: View {
    @ObservedObject public var props = TermuxProperties.shared
    
    public init() {}
    
    public var body: some View {
        Form {
            Section(header: Text("AVAILABLE THEMES")) {
                ForEach(TermuxTheme.allThemes) { theme in
                    Button(action: {
                        props.currentTheme = theme
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 4) {
                                    ForEach(0..<min(8, theme.ansiColorsHex.count), id: \.self) { idx in
                                        Circle()
                                            .fill(Color(hex: theme.ansiColorsHex[idx]))
                                            .frame(width: 14, height: 14)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if props.currentTheme == theme {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Color Scheme")
    }
}
