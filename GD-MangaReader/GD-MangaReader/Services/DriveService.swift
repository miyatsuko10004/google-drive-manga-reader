// DriveService.swift
// GD-MangaReader
//
// Google Drive API通信を担当するサービス

import Foundation
import GoogleAPIClientForREST_Drive
import GoogleSignIn

/// Google Drive APIとの通信を担当するサービス
actor DriveService {
    // MARK: - Properties
    
    private let service: GTLRDriveService
    
    // MARK: - Initialization
    
    init() {
        self.service = GTLRDriveService()
    }
    
    // MARK: - Configuration
    
    /// 認証情報を設定
    func configure(with authorizer: any GTMFetcherAuthorizationProtocol) {
        service.authorizer = authorizer
    }
    
    // MARK: - File List
    
    /// 指定フォルダ内のファイル一覧を取得
    /// - Parameters:
    ///   - folderId: フォルダID（nilの場合はルート）
    ///   - pageToken: ページネーション用トークン
    /// - Returns: ファイル一覧と次ページトークン
    func listFiles(
        in folderId: String? = nil,
        pageToken: String? = nil
    ) async throws -> (items: [DriveItem], nextPageToken: String?) {
        let query = GTLRDriveQuery_FilesList.query()
        
        // 検索クエリの構築
        let parentId = folderId ?? "root"
        let mimeTypeConditions = Config.SupportedFormats.mimeTypes
            .map { "mimeType='\($0)'" }
            .joined(separator: " or ")
        
        query.q = "'\(parentId)' in parents and trashed=false and (\(mimeTypeConditions))"
        
        // 取得するフィールドを指定
        query.fields = "nextPageToken, files(id, name, mimeType, size, thumbnailLink, parents, createdTime, modifiedTime)"
        
        // ソート順（フォルダ優先、名前順）
        query.orderBy = "folder, name"
        
        // ページサイズ
        query.pageSize = 50
        
        // ページトークン
        query.pageToken = pageToken
        
        // APIリクエスト実行
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GTLRDrive_FileList, Error>) in
            service.executeQuery(query) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let fileList = result as? GTLRDrive_FileList {
                    continuation.resume(returning: fileList)
                } else {
                    continuation.resume(throwing: DriveServiceError.invalidResponse)
                }
            }
        }
        
        // GTLRDrive_FileからDriveItemへの変換
        let items = (result.files ?? []).compactMap { file -> DriveItem? in
            guard let id = file.identifier, let name = file.name, let mimeType = file.mimeType else {
                return nil
            }
            
            return DriveItem(
                id: id,
                name: name,
                mimeType: mimeType,
                size: file.size?.int64Value,
                thumbnailURL: file.thumbnailLink.flatMap { URL(string: $0) },
                parentId: file.parents?.first,
                createdTime: file.createdTime?.date,
                modifiedTime: file.modifiedTime?.date
            )
        }
        
        return (items, result.nextPageToken)
    }
    
    /// ファイルのダウンロードURLを取得
    /// - Parameter fileId: ファイルID
    /// - Returns: ダウンロード用URLRequest
    func getDownloadRequest(for fileId: String) async throws -> URLRequest {
        let baseURL = "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media"
        guard let url = URL(string: baseURL) else {
            throw DriveServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        // 認証ヘッダーを追加
        guard let authorizer = service.authorizer else {
            throw DriveServiceError.authorizationFailed
        }
        
        let authorizedRequest: URLRequest = try await withCheckedThrowingContinuation { continuation in
            authorizer.authorizeRequest(request) { authRequest, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let authRequest = authRequest {
                    continuation.resume(returning: authRequest)
                } else {
                    continuation.resume(throwing: DriveServiceError.authorizationFailed)
                }
            }
        }
        
        return authorizedRequest
    }
    
    /// フォルダ内の画像ファイル一覧を取得（画像フォルダ閲覧用）
    func listImages(in folderId: String) async throws -> [DriveItem] {
        let query = GTLRDriveQuery_FilesList.query()
        
        let imageConditions = Config.SupportedFormats.imageExtensions
            .map { ext in "name contains '.\(ext)'" }
            .joined(separator: " or ")
        
        query.q = "'\(folderId)' in parents and trashed=false and (\(imageConditions))"
        query.fields = "files(id, name, mimeType, size, thumbnailLink, parents)"
        query.orderBy = "name"
        query.pageSize = 500 // 画像は多い可能性があるため大きめに
        
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GTLRDrive_FileList, Error>) in
            service.executeQuery(query) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let fileList = result as? GTLRDrive_FileList {
                    continuation.resume(returning: fileList)
                } else {
                    continuation.resume(throwing: DriveServiceError.invalidResponse)
                }
            }
        }
        
        return (result.files ?? []).compactMap { file -> DriveItem? in
            guard let id = file.identifier, let name = file.name, let mimeType = file.mimeType else {
                return nil
            }
            
            return DriveItem(
                id: id,
                name: name,
                mimeType: mimeType,
                size: file.size?.int64Value,
                thumbnailURL: file.thumbnailLink.flatMap { URL(string: $0) },
                parentId: file.parents?.first,
                createdTime: nil,
                modifiedTime: nil
            )
        }
    }
}

// MARK: - Errors

enum DriveServiceError: LocalizedError {
    case invalidResponse
    case invalidURL
    case authorizationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "無効なレスポンスを受信しました"
        case .invalidURL:
            return "無効なURLです"
        case .authorizationFailed:
            return "認証に失敗しました"
        }
    }
}
