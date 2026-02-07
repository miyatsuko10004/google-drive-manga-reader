// LoginView.swift
// GD-MangaReader
//
// Googleサインイン画面

import SwiftUI
import GoogleSignInSwift

/// Googleサインイン画面
struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // アプリアイコン・タイトル
                VStack(spacing: 16) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("GD-MangaReader")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Google Driveの漫画を読もう")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // サインインボタン
                VStack(spacing: 20) {
                    if authViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else {
                        GoogleSignInButton(
                            viewModel: GoogleSignInButtonViewModel(
                                scheme: .light,
                                style: .wide,
                                state: .normal
                            )
                        ) {
                            Task {
                                await authViewModel.signIn()
                            }
                        }
                        .frame(width: 280, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    // エラーメッセージ
                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // フッター
                Text("Powered by Google Drive API")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom)
            }
            .padding()
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
