//
//  AppSelectionView.swift
//  JITAllower
//
//  Sheet selector to enable JIT on all apps simultaneously or pick an individual app.
//

import SwiftUI

public struct AppSelectionView: View {
    @ObservedObject public var manager = JITManager.shared
    @Environment(\.presentationMode) private var presentationMode
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("QUICK ACTION (ALL APPS)")) {
                    Button(action: {
                        manager.enableJITForAllApps()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 40, height: 40)
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20, weight: .bold))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable JIT on ALL Apps")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Unlock JIT for every installed/running app at once")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("INDIVIDUAL APPLICATIONS (TROLLSTORE & SIDELOADED)")) {
                    ForEach(manager.apps) { app in
                        Button(action: {
                            manager.enableJIT(forApp: app)
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(app.isJITEnabled ? Color.green : Color.blue.opacity(0.8))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: app.isJITEnabled ? "checkmark.shield.fill" : "app.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 18))
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text(app.bundleID)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if app.isJITEnabled {
                                    Text("JIT ON")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(4)
                                } else {
                                    Text("SELECT")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Select JIT Targets")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
