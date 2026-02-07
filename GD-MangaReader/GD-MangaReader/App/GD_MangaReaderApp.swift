// GD_MangaReaderApp.swift
// GD-MangaReader
//
// Created by Developer

import SwiftUI
import GoogleSignIn

@main
struct GD_MangaReaderApp: App {
    @State private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

/// ルートコンテンツビュー - 認証状態に応じて表示を切り替え
struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    var body: some View {
        Group {
            if authViewModel.isSignedIn {
                LibraryView()
            } else {
                LoginView()
            }
        }
        .task {
            await authViewModel.restorePreviousSignIn()
        }
    }
}
