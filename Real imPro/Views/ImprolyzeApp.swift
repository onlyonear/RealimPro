//
//  ImprolyzeApp.swift
//  Improlyze
//
//  Created by OnlyOnear on 2026/6/16.
//

import SwiftUI

@main
struct ImprolyzeApp: App {
    @StateObject private var iap = IAPManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(iap)
        }
    }
}
