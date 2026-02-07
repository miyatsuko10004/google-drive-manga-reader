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
    private var rootFolderId: String?
    private var accessToken: String?
    
    // MARK: - Initialization
    
    init() {
        self.service = GTLRDriveService()
        self.service.shouldFetchNextPages = true
        self.service.isRetryEnabled = true
    }
    
    // MARK: - Configuration
    
    /// 認証情報を設定
    func configure(with authorizer: any GTMFetcherAuthorizationProtocol) {
        service.authorizer = authorizer
    }
    
    /// アクセストークンを設定（直接ダウンロード用）
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }
    
    // MARK: - Root Folder
    
    /// ルートフォルダ("manga")のIDを取得・特定する
    func fetchRootFolderId() async throws -> String {
        // すでに取得済みならそれを返す
        if let cachedId = rootFolderId {
            return cachedId
        }
        
        // 1. ConfigのデフォルトIDを試す（開発用）
        if let defaultId = Config.GoogleAPI.defaultFolderId {
            // IDが有効か確認（実際にアクセスできるか）
            do {
                let query = GTLRDriveQuery_FilesGet.query(withFileId: defaultId)
                query.fields = "id, name, trashed"
                let file = try await executeFileGetQuery(query)
                
                if file.trashed?.boolValue != true {
                    print("✅ [DriveService] Default root folder found: \(defaultId)")
                    self.rootFolderId = defaultId
                    return defaultId
                }
            } catch {
                print("⚠️ [DriveService] Default folder ID invalid or inaccessible: \(error.localizedDescription)")
            }
        }
        
        // 2. 名前で検索 ("manga" フォルダ)
        print("🔍 [DriveService] Searching for root folder named '\(Config.GoogleAPI.rootFolderName)'")
        let query = GTLRDriveQuery_FilesList.query()
        query.q = "mimeType = 'application/vnd.google-apps.folder' and name = '\(Config.GoogleAPI.rootFolderName)' and trashed = false"
        query.fields = "files(id, name)"
        
        let result = try await executeFileListQuery(query)
        
        if let folder = result.files?.first, let id = folder.identifier {
            print("✅ [DriveService] Found root folder by name: \(id)")
            self.rootFolderId = id
            return id
        }
        
        throw DriveServiceError.rootFolderNotFound
    }
    
    // MARK: - File List
    
    /// 指定フォルダ内のファイル一覧を取得
    func listFiles(
        in folderId: String? = nil,
        pageToken: String? = nil
    ) async throws -> (items: [DriveItem], nextPageToken: String?) {
        
        // ルートフォルダが未特定の場合は特定する
        let targetFolderId: String
        if let folderId = folderId {
            targetFolderId = folderId
        } else {
            // folderIdがnil（ルート要求）の場合、mangaフォルダをルートとする
            targetFolderId = try await fetchRootFolderId()
        }
        
        let query = GTLRDriveQuery_FilesList.query()
        
        let mimeTypeConditions = Config.SupportedFormats.mimeTypes
            .map { "mimeType='\($0)'" }
            .joined(separator: " or ")
        
        // 拡張子による検索条件を追加（MIMEタイプが正しく付与されていない場合対策）
        let archiveExtensionConditions = Config.SupportedFormats.archiveExtensions
            .map { "name contains '.\($0)'" }
        
        let imageExtensionConditions = Config.SupportedFormats.imageExtensions
            .map { "name contains '.\($0)'" }
            
        let allExtensionConditions = (archiveExtensionConditions + imageExtensionConditions)
            .joined(separator: " or ")
        
        query.q = "'\(targetFolderId)' in parents and trashed=false and (\(mimeTypeConditions) or \(allExtensionConditions))"
        query.fields = "nextPageToken, files(id, name, mimeType, size, thumbnailLink, parents, createdTime, modifiedTime)"
        query.orderBy = "folder, name"
        query.pageSize = 50
        query.pageToken = pageToken
        
        let result = try await executeFileListQuery(query)
        
        print("🔍 [DriveService] Found \(result.files?.count ?? 0) files in folder \(targetFolderId)")
        
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
        
        let result = try await executeFileListQuery(query)
        
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
    
    /// ファイルデータを直接ダウンロード（ストリーミング閲覧用）
    func downloadFileData(fileId: String) async throws -> Data {
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("❌ [DriveService] Download failed: \(response)")
            throw DriveServiceError.invalidResponse
        }
        
        return data
    }
    
    // MARK: - Private Methods
    
    /// GTLRクエリを実行（スレッドセーフ）
    private func executeFileListQuery(_ query: GTLRDriveQuery_FilesList) async throws -> GTLRDrive_FileList {
        try await withCheckedThrowingContinuation { continuation in
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
    }
    /// GTLRクエリを実行（Files.Get用）
    private func executeFileGetQuery(_ query: GTLRDriveQuery_FilesGet) async throws -> GTLRDrive_File {
        try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let file = result as? GTLRDrive_File {
                    continuation.resume(returning: file)
                } else {
                    continuation.resume(throwing: DriveServiceError.invalidResponse)
                }
            }
        }
    }
}

// MARK: - Errors

enum DriveServiceError: LocalizedError {
    case invalidResponse
    case invalidURL
    case authorizationFailed
    case rootFolderNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "無効なレスポンスを受信しました"
        case .invalidURL:
            return "無効なURLです"
        case .authorizationFailed:
            return "認証に失敗しました"
        case .rootFolderNotFound:
            return "ルートフォルダ('manga')が見つかりませんでした"
        }
    }
}
