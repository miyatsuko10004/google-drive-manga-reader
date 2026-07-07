// GD_MangaReaderApp.swift
// GD-MangaReader
//
// Created by Developer

import SwiftUI
import GoogleSignIn

@main
struct GD_MangaReaderApp: App {
    @State private var authViewModel = AuthViewModel()
    
    init() {
        print("🚀 [APP] GD_MangaReaderApp init")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .onOpenURL { url in
                    print("📱 [APP] onOpenURL: \(url)")
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    print("✅ [APP] ContentView appeared")
                }
        }
    }
}

/// ルートコンテンツビュー - 認証状態に応じて表示を切り替え
struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    var body: some View {
        Group {
            if authViewModel.isOfflineMode || authViewModel.isSignedIn {
                LibraryView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            print("🔍 [CONTENT] isSignedIn = \(authViewModel.isSignedIn)")
        }
        .task {
            print("⏳ [CONTENT] Starting restorePreviousSignIn")
            // FIXME: Tuning off restorePreviousSignIn to prevent crash on launch
            await authViewModel.restorePreviousSignIn()
            print("✅ [CONTENT] restorePreviousSignIn completed (skipped), isSignedIn = \(authViewModel.isSignedIn)")
        }
    }
}
