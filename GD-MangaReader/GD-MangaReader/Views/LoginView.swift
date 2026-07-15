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

            // Dynamic Type拡大時や小型端末で内容が画面高を超えても、サインイン／
            // オフライン操作へスクロールで到達できるようにする。
            // minHeightを画面高に合わせることで、内容が収まる通常時は
            // Spacerが効いて従来どおりの中央寄せレイアウトになる
            GeometryReader { proxy in
                ScrollView {
                    loginContent
                        .frame(maxWidth: 500) // iPadなどで横に広がりすぎないようにする
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
        }
    }

    private var loginContent: some View {
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
                    // Dynamic Typeで拡大縮小できるようfixed sizeではなくスタイル指定にする
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
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
                    VStack(spacing: 16) {
                        // 既知の制限: GoogleSignInButtonはサードパーティ製のUIKitラッパーで、
                        // 内部のフォントがDynamic Typeに追従しない可能性がある。
                        // 外側のframeを最小値のみの指定にして、少なくとも枠は拡大を妨げないようにする
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
                        // 幅・高さは最小値のみ固定し、Dynamic Typeでの拡大に追従できるようにする
                        .frame(minWidth: 280, minHeight: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

                        Button(action: {
                            authViewModel.setOfflineMode(true)
                        }) {
                            Text("オフラインで利用")
                                // Dynamic Typeに追従するテキストスタイルと、
                                // 固定frameの代わりにパディング＋最小サイズでボタンを構成する
                                .font(.body.weight(.medium))
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .frame(minWidth: 280, minHeight: 50)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 3)
                    }
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

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
