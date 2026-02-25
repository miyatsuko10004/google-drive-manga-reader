// LibraryView.swift
// GD-MangaReader
//
// Google Drive内のファイルブラウザ画面

import SwiftUI
import Kingfisher

/// Driveファイルブラウザ画面
struct LibraryView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var libraryViewModel = LibraryViewModel()
    @State private var bulkDownloadManager = BulkDownloadManager()
    @State private var selectedItem: DriveItem?
    @State private var showingSignOutAlert = false
    @State private var readingSession: ComicSession?
    @State private var showingBulkDownloadConfirmation = false
    @State private var selectedFolderForBulk: DriveItem?
    @State private var localRefreshTrigger = 0
    @State private var toast: ToastData?
    
    struct ComicSession: Identifiable {
        var id: String { source.id }
        let source: any ComicSource
    }
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if libraryViewModel.isLoading && libraryViewModel.items.isEmpty {
                    // 初回ローディング
                    shimmerLoadingView
                } else if let error = libraryViewModel.errorMessage {
                    // エラー表示
                    errorView(message: error)
                } else if libraryViewModel.items.isEmpty {
                    // 空の状態
                    emptyView
                } else {
                    // ファイル一覧
                    fileListContent
                }
                
                // 一括ダウンロードプログレスバナー
                if bulkDownloadManager.isDownloading {
                    VStack {
                        Spacer()
                        bulkDownloadBanner
                    }
                }
            }
            .toastView(toast: $toast)
            .navigationTitle(libraryViewModel.currentFolderName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                toolbarContent
            }
            .searchable(text: $libraryViewModel.searchText, prompt: "作品・フォルダを検索")
            .refreshable {
                await libraryViewModel.refresh()
            }
            .task {
                libraryViewModel.configure(with: authViewModel.authorizer)
                await libraryViewModel.loadFiles()
            }
            .alert("サインアウト", isPresented: $showingSignOutAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("サインアウト", role: .destructive) {
                    authViewModel.signOut()
                }
            } message: {
                Text("サインアウトしますか？")
            }
            .alert("シリーズ一括ダウンロード", isPresented: $showingBulkDownloadConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ダウンロード") {
                    if let folder = selectedFolderForBulk {
                        bulkDownloadManager.downloadSeries(
                            folder: folder,
                            driveService: libraryViewModel.driveService,
                            authorizer: authViewModel.authorizer,
                            accessToken: authViewModel.accessToken,
                            onComplete: { failedCount in
                                if failedCount == 0 {
                                    toast = ToastData(title: "ダウンロード完了", message: "\(folder.name) のダウンロードが完了しました", type: .success)
                                } else {
                                    toast = ToastData(title: "ダウンロード完了 (\(failedCount)件失敗)", message: "\(folder.name) のダウンロードが完了しましたが、一部失敗しました", type: .error)
                                }
                            },
                            onError: { error in
                                toast = ToastData(title: "ダウンロード失敗", message: error.localizedDescription, type: .error)
                            }
                        )
                        toast = ToastData(title: "ダウンロード開始", message: "\(folder.name) のダウンロードを開始しました", type: .info)
                    }
                }
            } message: {
                if let folder = selectedFolderForBulk {
                    Text("\(folder.name)内のアーカイブを一括ダウンロードします。")
                }
            }
            .onChange(of: selectedItem) { _, newValue in
                if newValue == nil {
                    localRefreshTrigger += 1
                }
            }
            .sheet(item: $selectedItem) { item in
                // ダウンロードターゲットを決定
                let target: DownloadTarget = {
                    if item.isArchive {
                        return .file(item)
                    } else {
                        // 画像ファイルの場合は親フォルダをダウンロード
                        return .folder(
                            id: libraryViewModel.currentFolderId ?? "root",
                            name: libraryViewModel.currentFolderName
                        )
                    }
                }()
                
                DownloadSheet(
                    target: target,
                    isPresented: Binding(
                        get: { self.selectedItem != nil },
                        set: { if !$0 { self.selectedItem = nil } }
                    ),
                    onComplete: { comic in
                        // ローカルコミックとして開く
                        self.selectedItem = nil
                        readingSession = ComicSession(source: LocalComicSource(comic: comic))
                    }
                )
            }
            .fullScreenCover(item: $readingSession) { session in
                ReaderView(source: session.source)
            }
        }
    }
    

    // MARK: - Subviews
    
    /// ファイル一覧コンテンツ
    @ViewBuilder
    private var fileListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 最近読んだ作品（ルート階層でのみ表示）
                if libraryViewModel.folderPath.isEmpty && !libraryViewModel.recentComics.isEmpty {
                    RecentComicsShelfView(
                        readingSession: $readingSession,
                        recentComics: libraryViewModel.recentComics
                    )
                    Divider().padding(.vertical, 8)
                }
                
                // パンくずリスト
                if !libraryViewModel.folderPath.isEmpty {
                    breadcrumbView
                }
                
                // アイテム一覧
                switch libraryViewModel.viewMode {
                case .grid:
                    DriveItemGridView(
                        gridColumns: gridColumns,
                        libraryViewModel: libraryViewModel,
                        bulkDownloadManager: bulkDownloadManager,
                        selectedFolderForBulk: $selectedFolderForBulk,
                        showingBulkDownloadConfirmation: $showingBulkDownloadConfirmation,
                        onItemTap: handleItemTap
                    )
                case .list:
                    DriveItemListView(
                        libraryViewModel: libraryViewModel,
                        bulkDownloadManager: bulkDownloadManager,
                        selectedFolderForBulk: $selectedFolderForBulk,
                        showingBulkDownloadConfirmation: $showingBulkDownloadConfirmation,
                        onItemTap: handleItemTap
                    )
                }
                
                // さらに読み込み
                if libraryViewModel.hasMoreItems {
                    autoLoadMoreView
                }
            }
            .padding()
        }
    }
    
    
    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    Task { await libraryViewModel.navigateToRoot() }
                } label: {
                    Label("マイドライブ", systemImage: "house")
                        .font(.caption)
                }
                
                ForEach(libraryViewModel.folderPath) { folder in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button(folder.name) {
                        // TODO: 中間フォルダへの直接ジャンプ
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    /// さらに読み込みトリガー
    private var autoLoadMoreView: some View {
        Color.clear
            .frame(height: 20)
            .id(UUID()) // 常に再描画させて発火を促す
            .onAppear {
                if libraryViewModel.hasMoreItems {
                    Task { await libraryViewModel.loadMoreFiles() }
                }
            }
    }
    
    /// スケルトンUI（Shimmer）
    private var shimmerLoadingView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(0..<12, id: \.self) { _ in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .aspectRatio(1, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(height: 14)
                            .padding(.horizontal, 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(width: 50, height: 10)
                    }
                    .padding(8)
                    .shimmer()
                }
            }
            .padding()
        }
    }
    
    /// 空の状態表示
    private var emptyView: some View {
        ContentUnavailableView(
            "ファイルがありません",
            systemImage: "folder.badge.questionmark",
            description: Text("このフォルダには対応ファイルがありません\n(ZIP, RAR, CBZ, CBR)")
        )
    }
    
    /// エラー表示
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "エラーが発生しました",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            
            Button("再試行") {
                Task { await libraryViewModel.loadFiles() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    /// 一括ダウンロードバナー
    private var bulkDownloadBanner: some View {
        HStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("一括ダウンロード中...")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                HStack {
                    ProgressView(
                        value: Double(bulkDownloadManager.currentCount),
                        total: Double(max(1, bulkDownloadManager.totalCount))
                    )
                    .progressViewStyle(.linear)
                    .tint(.green)
                    
                    Text("\(bulkDownloadManager.currentCount) / \(bulkDownloadManager.totalCount)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding()
        .shadow(radius: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: bulkDownloadManager.isDownloading)
    }
    
    /// ツールバー
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !libraryViewModel.folderPath.isEmpty {
                Button {
                    Task { await libraryViewModel.navigateBack() }
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                // 表示切り替え
                Picker("表示モード", selection: $libraryViewModel.viewMode) {
                    ForEach(LibraryViewModel.ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                
                // 並び替えオプション
                Picker("並び替え", selection: $libraryViewModel.sortOption) {
                    ForEach(LibraryViewModel.SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                
                Divider()
                
                // ユーザー情報
                Section {
                    Text(authViewModel.userName)
                    Text(authViewModel.userEmail)
                        .font(.caption)
                }
                
                Divider()
                
                // ストレージ管理
                NavigationLink {
                    StorageManagementView()
                } label: {
                    Label("ストレージ管理", systemImage: "externaldrive")
                }
                
                Divider()
                
                // サインアウト
                Button(role: .destructive) {
                    showingSignOutAlert = true
                } label: {
                    Label("サインアウト", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleItemTap(_ item: DriveItem) {
        if item.isFolder {
            Task { await libraryViewModel.navigateToFolder(item) }
        } else if item.isArchive {
            // ダウンロード済みか確認
            if let existingComic = try? LocalStorageService.shared.findComic(byDriveFileId: item.id),
               existingComic.status == .completed {
                // ダウンロード済み → 直接リーダーを開く
                readingSession = ComicSession(source: LocalComicSource(comic: existingComic))
            } else {
                // 未ダウンロード → ダウンロードシートを表示
                selectedItem = item
            }
        } else if item.isImage {
            // 画像ファイルはストリーミング閲覧開始
            startStreamingRead(from: item)
        }
    }
    
    /// ストリーミング閲覧を開始
    private func startStreamingRead(from item: DriveItem) {
        // 現在のフォルダ内の全画像を取得
        let images = libraryViewModel.items.filter { $0.isImage }
        guard !images.isEmpty else { return }
        
        // アクセストークンをセット（重要: これがないと画像データがダウンロードできない）
        libraryViewModel.driveService.setAccessToken(authViewModel.accessToken)
        
        // タップした画像のインデックスを特定
        let initialIndex = images.firstIndex(where: { $0.id == item.id }) ?? 0
        
        // RemoteComicSourceを作成
        let source = RemoteComicSource(
            folderId: libraryViewModel.currentFolderId ?? "root",
            title: libraryViewModel.currentFolderName,
            files: images,
            driveService: libraryViewModel.driveService
        )
        
        // 初期ページを設定
        Task {
            await source.saveProgress(page: initialIndex)
            await MainActor.run {
                readingSession = ComicSession(source: source)
            }
        }
    }
}

// MARK: - Grid Cell

/// グリッド表示用セル
struct DriveItemGridCell: View {
    let item: DriveItem
    let isBulkDownloading: Bool
    let localComic: LocalComic?
    let folderThumbnails: [URL]?
    
    private var isDownloaded: Bool { localComic != nil }
    private var localThumbnailURL: URL? { localComic?.imagePaths.first }
    private var readingProgress: Double { localComic?.readingProgress ?? 0.0 }
    
    var body: some View {
        VStack(spacing: 8) {
            // サムネイル / アイコン
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(1, contentMode: .fit)
                
                if let thumbnailURL = item.thumbnailURL {
                    KFImage(thumbnailURL)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let localThumbnailURL = localThumbnailURL {
                    KFImage(localThumbnailURL)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if item.isFolder, let folderThumbnails = folderThumbnails, !folderThumbnails.isEmpty {
                    // フォルダ用 サムネイルタイル
                    FolderThumbnailView(urls: folderThumbnails)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: 40))
                        .foregroundColor(iconColor)
                }
                
                // 読了プログレスバー
                if isDownloaded && readingProgress > 0 {
                    VStack {
                        Spacer()
                        ProgressView(value: readingProgress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .background(Color.white.opacity(0.8))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .overlay(alignment: .topTrailing) {
                if isBulkDownloading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .background(Circle().fill(.white).frame(width: 24, height: 24).shadow(radius: 2))
                        .offset(x: 4, y: -4)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                        .background(Circle().fill(.white).frame(width: 18, height: 18))
                        .offset(x: 4, y: -4)
                }
            }
            
            // ファイル名
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            // サイズ
            if !item.isFolder {
                Text(item.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
    }
    
    private var iconColor: Color {
        if item.isFolder {
            return .blue
        } else if item.isArchive {
            return .orange
        } else if Config.SupportedFormats.imageExtensions.contains(item.fileExtension.lowercased()) {
            return .purple
        }
        return .gray
    }
}

// MARK: - List Row

/// リスト表示用行
struct DriveItemListRow: View {
    let item: DriveItem
    let isBulkDownloading: Bool
    let localComic: LocalComic?
    let folderThumbnails: [URL]?
    
    private var isDownloaded: Bool { localComic != nil }
    private var localThumbnailURL: URL? { localComic?.imagePaths.first }
    private var readingProgress: Double { localComic?.readingProgress ?? 0.0 }
    
    var body: some View {
        HStack(spacing: 12) {
            // アイコン
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 44, height: 44)
                
                if let localThumbnailURL = localThumbnailURL {
                    KFImage(localThumbnailURL)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else if item.isFolder, let folderThumbnails = folderThumbnails, !folderThumbnails.isEmpty {
                    // フォルダ用 サムネイルタイル
                    FolderThumbnailView(urls: folderThumbnails)
                        .clipShape(Circle())
                } else {
                    Image(systemName: item.iconName)
                        .font(.title3)
                        .foregroundColor(iconColor)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isBulkDownloading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .background(Circle().fill(.white).frame(width: 16, height: 16).shadow(radius: 1))
                        .offset(x: 2, y: -2)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .background(Circle().fill(.white).frame(width: 12, height: 12))
                        .offset(x: 2, y: -2)
                }
            }
            
            // ファイル情報
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                
                if isDownloaded && readingProgress > 0 {
                    ProgressView(value: readingProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(height: 4)
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                }
                
                HStack {
                    if !item.isFolder {
                        Text(item.formattedSize)
                    }
                    if let modifiedTime = item.modifiedTime {
                        Text(modifiedTime, style: .date)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 矢印
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var iconColor: Color {
        if item.isFolder {
            return .blue
        } else if item.isArchive {
            return .orange
        } else if Config.SupportedFormats.imageExtensions.contains(item.fileExtension.lowercased()) {
            return .purple
        }
        return .gray
    }
}

#Preview {
    LibraryView()
        .environment(AuthViewModel())
}

// MARK: - Folder Thumbnail View

/// フォルダ内の画像サムネイルを格子状に表示するビュー
struct FolderThumbnailView: View {
    let urls: [URL]
    
    var body: some View {
        GeometryReader { geometry in
            let cols = 2
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(cols - 1)
            let itemSize = (geometry.size.width - totalSpacing) / CGFloat(cols)
            
            LazyVGrid(columns: [
                GridItem(.fixed(itemSize), spacing: spacing),
                GridItem(.fixed(itemSize), spacing: spacing)
            ], spacing: spacing) {
                // 最大4つまで表示
                ForEach(0..<min(urls.count, 4), id: \.self) { index in
                    KFImage(urls[index])
                        .resizable()
                        .scaledToFill()
                        .frame(width: itemSize, height: itemSize)
                        .clipped()
                }
            }
        }
        .background(Color(.systemGray5))
    }
}
