// AuthViewModel.swift
// GD-MangaReader
//
// Google認証状態を管理するViewModel

import Foundation
import GoogleSignIn
import GoogleAPIClientForREST_Drive

/// Google認証状態を管理するViewModel
@MainActor
@Observable
final class AuthViewModel {
    // MARK: - Properties
    
    /// サインイン状態
    private(set) var isSignedIn: Bool = false
    
    /// ユーザー名
    private(set) var userName: String = ""
    
    /// ユーザーのメールアドレス
    private(set) var userEmail: String = ""
    
    /// ユーザーのプロフィール画像URL
    private(set) var userProfileImageURL: URL?
    
    /// エラーメッセージ
    private(set) var errorMessage: String?
    
    /// ローディング状態
    private(set) var isLoading: Bool = false
    
    /// 現在のGoogleユーザー
    private(set) var currentUser: GIDGoogleUser?
    
    // MARK: - Computed Properties
    
    /// Drive APIサービス用のauthorizer
    var authorizer: (any GTMSessionFetcherAuthorizer)? {
        currentUser?.fetcherAuthorizer as? any GTMSessionFetcherAuthorizer
    }
    
    /// アクセストークン（ダウンロード認証用）
    var accessToken: String? {
        currentUser?.accessToken.tokenString
    }
    
    // MARK: - Methods
    
    /// 前回のサインイン情報を復元
    func restorePreviousSignIn() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if GIDSignIn.sharedInstance.hasPreviousSignIn() {
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                await handleSignInSuccess(user: user)
            }
        } catch {
            print("Failed to restore previous sign in: \(error.localizedDescription)")
            // 前回のサインイン復元失敗は無視（ユーザーに再度サインインを促す）
        }
    }
    
    /// Googleサインインを実行
    func signIn() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        guard let presentingViewController = await getRootViewController() else {
            errorMessage = "画面の取得に失敗しました"
            return
        }
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: Config.GoogleAPI.scopes
            )
            await handleSignInSuccess(user: result.user)
        } catch {
            handleSignInError(error)
        }
    }
    
    /// サインアウト
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userName = ""
        userEmail = ""
        userProfileImageURL = nil
        currentUser = nil
    }
    
    // MARK: - Private Methods
    
    /// サインイン成功時の処理
    private func handleSignInSuccess(user: GIDGoogleUser) async {
        currentUser = user
        userName = user.profile?.name ?? "Unknown"
        userEmail = user.profile?.email ?? ""
        userProfileImageURL = user.profile?.imageURL(withDimension: 100)
        
        // Drive APIスコープが許可されているか確認
        let grantedScopes = user.grantedScopes ?? []
        let hasDriveScope = grantedScopes.contains(Config.GoogleAPI.driveReadOnlyScope)
        
        if !hasDriveScope {
            // スコープが不足している場合は追加で要求
            do {
                guard let presentingViewController = await getRootViewController() else {
                    errorMessage = "画面の取得に失敗しました"
                    return
                }
                let result = try await user.addScopes(
                    Config.GoogleAPI.scopes,
                    presenting: presentingViewController
                )
                currentUser = result.user
            } catch {
                errorMessage = "Drive APIへのアクセス許可が必要です"
                return
            }
        }
        
        isSignedIn = true
    }
    
    /// サインインエラーのハンドリング
    private func handleSignInError(_ error: Error) {
        let nsError = error as NSError
        
        // ユーザーキャンセルの場合はエラー表示しない
        if nsError.domain == kGIDSignInErrorDomain,
           nsError.code == GIDSignInError.canceled.rawValue {
            return
        }
        
        errorMessage = error.localizedDescription
    }
    
    /// ルートViewControllerを取得
    @MainActor
    private func getRootViewController() async -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        
        // presentされているViewControllerがあればそれを返す
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        return topController
    }
}
