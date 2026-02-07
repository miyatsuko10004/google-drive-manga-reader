// DriveService.swift
// GD-MangaReader
//
// Google Drive API通信を担当するサービス

import Foundation
import GoogleAPIClientForREST_Drive
import GoogleSignIn

/// Google Drive APIとの通信を担当するサービス
@MainActor
final class DriveService {
    // MARK: - Properties
    
    private let service: GTLRDriveService
    private var accessToken: String?
    
    // MARK: - Initialization
    
    init() {
        self.service = GTLRDriveService()
    }
    
    // MARK: - Configuration
    
    /// 認証情報を設定
    func configure(with authorizer: any GTMFetcherAuthorizationProtocol) {
        service.authorizer = authorizer
    }
    
    /// アクセストークンを設定（ダウンロード用）
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }
    
    // MARK: - File List
    
    /// 指定フォルダ内のファイル一覧を取得
    func listFiles(
        in folderId: String? = nil,
        pageToken: String? = nil
    ) async throws -> (items: [DriveItem], nextPageToken: String?) {
        let query = GTLRDriveQuery_FilesList.query()
        
        let parentId = folderId ?? "root"
        let mimeTypeConditions = Config.SupportedFormats.mimeTypes
            .map { "mimeType='\($0)'" }
            .joined(separator: " or ")
        
        query.q = "'\(parentId)' in parents and trashed=false and (\(mimeTypeConditions))"
        query.fields = "nextPageToken, files(id, name, mimeType, size, thumbnailLink, parents, createdTime, modifiedTime)"
        query.orderBy = "folder, name"
        query.pageSize = 50
        query.pageToken = pageToken
        
        let result: GTLRDrive_FileList = try await withCheckedThrowingContinuation { continuation in
            self.service.executeQuery(query) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let fileList = result as? GTLRDrive_FileList {
                    continuation.resume(returning: fileList)
                } else {
                    continuation.resume(throwing: DriveServiceError.invalidResponse)
                }
            }
        }
        
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
    func getDownloadRequest(for fileId: String) async throws -> URLRequest {
        let baseURL = "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media"
        guard let url = URL(string: baseURL) else {
            throw DriveServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        // アクセストークンで認証
        guard let token = accessToken else {
            throw DriveServiceError.authorizationFailed
        }
        
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    /// フォルダ内の画像ファイル一覧を取得
    func listImages(in folderId: String) async throws -> [DriveItem] {
        let query = GTLRDriveQuery_FilesList.query()
        
        let imageConditions = Config.SupportedFormats.imageExtensions
            .map { ext in "name contains '.\(ext)'" }
            .joined(separator: " or ")
        
        query.q = "'\(folderId)' in parents and trashed=false and (\(imageConditions))"
        query.fields = "files(id, name, mimeType, size, thumbnailLink, parents)"
        query.orderBy = "name"
        query.pageSize = 500
        
        let result: GTLRDrive_FileList = try await withCheckedThrowingContinuation { continuation in
            self.service.executeQuery(query) { _, result, error in
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
