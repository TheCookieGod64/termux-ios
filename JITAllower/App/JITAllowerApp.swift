//
//  JITAllowerApp.swift
//  JITAllower
//
//  @main SwiftUI entry point for JITAllower (iPhone 8 | palera1n | TrollStore).
//

import SwiftUI
import UIKit

@main
public struct JITAllowerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark)
        }
    }
}
