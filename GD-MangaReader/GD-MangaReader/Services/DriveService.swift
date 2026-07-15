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
    func configure(with authorizer: any GTMSessionFetcherAuthorizer) {
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
        
        query.q = "'\(targetFolderId)' in parents and trashed=false and (\(mimeTypeConditions) or \(allExtensionQuery))"
        query.fields = "nextPageToken, files(id, name, mimeType, size, thumbnailLink, parents, createdTime, modifiedTime, imageMediaMetadata)"
        query.orderBy = "folder, name"
        query.pageSize = 50
        query.pageToken = pageToken
        
        let result = try await executeFileListQuery(query)

        print("🔍 [DriveService] Found \(result.files?.count ?? 0) files in folder \(targetFolderId)")

        return (makeDriveItems(from: result), result.nextPageToken)
    }

    // MARK: - Search

    /// Driveのqクエリ（https://developers.google.com/drive/api/guides/search-files）の
    /// シングルクォート文字列リテラルへ安全に埋め込めるよう、ユーザー入力をエスケープする。
    /// バックスラッシュとシングルクォートをバックスラッシュでエスケープする
    /// （バックスラッシュを先に処理しないと、エスケープ用の`\`まで二重にエスケープされてしまう）。
    /// 純粋関数（ユニットテスト候補）
    static func escapeDriveQueryValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    /// ファイル名でDrive全体をサーバーサイド検索する（部分一致・ゴミ箱除外）。
    ///
    /// 注意（検索スコープの制限）: Drive APIのqクエリは「特定フォルダの子孫（深い階層）」という
    /// 条件を表現できない（`'x' in parents`は直下の子のみ）。祖先を再帰的に辿るフィルタは
    /// APIコールが多くコストが高いため実装せず、アプリがアクセスできるDrive全体を対象とする
    /// （＝mangaルートフォルダの外のファイルもヒットしうる）。
    ///
    /// 結果を「漫画らしい形」に保つため、対象はフォルダとアーカイブのみに絞る（画像は含めない）。
    func searchFiles(
        query userQuery: String,
        pageToken: String? = nil
    ) async throws -> (items: [DriveItem], nextPageToken: String?) {
        let escaped = Self.escapeDriveQueryValue(userQuery)

        // フォルダ + アーカイブのMIMEタイプ + アーカイブ拡張子（MIMEが不正確なファイル対策）
        let folderCondition = "mimeType='application/vnd.google-apps.folder'"
        let archiveMimeConditions = Config.SupportedFormats.mimeTypes
            .filter { $0 != "application/vnd.google-apps.folder" && !$0.hasPrefix("image/") }
            .map { "mimeType='\($0)'" }
        let archiveExtensionConditions = Config.SupportedFormats.archiveExtensions
            .sorted() // Setのため順序を安定させる
            .map { "name contains '.\($0)'" }
        let typeCondition = ([folderCondition] + archiveMimeConditions + archiveExtensionConditions)
            .joined(separator: " or ")

        let query = GTLRDriveQuery_FilesList.query()
        query.q = "name contains '\(escaped)' and trashed = false and (\(typeCondition))"
        query.fields = "nextPageToken, files(id, name, mimeType, size, thumbnailLink, parents, createdTime, modifiedTime, imageMediaMetadata)"
        query.orderBy = "folder, name"
        query.pageSize = 50
        query.pageToken = pageToken

        let result = try await executeFileListQuery(query)

        print("🔍 [DriveService] Search '\(userQuery)' found \(result.files?.count ?? 0) files")

        return (makeDriveItems(from: result), result.nextPageToken)
    }

    /// GTLRのファイルリストレスポンスをDriveItem配列へ変換する共通マッピング
    private func makeDriveItems(from result: GTLRDrive_FileList) -> [DriveItem] {
        (result.files ?? []).compactMap { file -> DriveItem? in
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
                modifiedTime: file.modifiedTime?.date,
                width: file.imageMediaMetadata?.width?.intValue,
                height: file.imageMediaMetadata?.height?.intValue
            )
        }
    }
    
    /// フォルダ内のアーカイブを全件（ページングしながら）取得し、自然順（巻数を数値として比較）にソートして返す
    /// Drive側の`orderBy=name`は単純な文字列比較のため「10巻」が「2巻」より前に来てしまうことがあり、
    /// "1巻"を確実に特定する用途にはこちらを使う
    func fetchArchivesNaturalSorted(inFolder folderId: String) async throws -> [DriveItem] {
        var allItems: [DriveItem] = []
        var token: String?
        repeat {
            let result = try await listFiles(in: folderId, pageToken: token)
            allItems.append(contentsOf: result.items)
            token = result.nextPageToken
        } while token != nil

        return allItems
            .filter { $0.isArchive }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private Helpers

    private var allExtensionQuery: String {
        let archiveConditions = Config.SupportedFormats.archiveExtensions
            .map { "name contains '.\($0)'" }
        let imageConditions = Config.SupportedFormats.imageExtensions
            .map { "name contains '.\($0)'" }
        return (archiveConditions + imageConditions).joined(separator: " or ")
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
        query.fields = "files(id, name, mimeType, size, thumbnailLink, parents, imageMediaMetadata)"
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
                modifiedTime: nil,
                width: file.imageMediaMetadata?.width?.intValue,
                height: file.imageMediaMetadata?.height?.intValue
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
