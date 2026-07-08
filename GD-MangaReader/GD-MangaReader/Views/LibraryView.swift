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
    @State private var selectedItem: DriveItem?
    @State private var showingSignOutAlert = false
    @State private var readingSession: ComicSession?
    @State private var showingBulkDownloadConfirmation = false
    @State private var selectedFolderForBulk: DriveItem?
    @State private var showingCascadeDownloadConfirmation = false
    @State private var selectedItemForCascade: DriveItem?
    @State private var showingDownloadQueue = false
    @State private var showingTrialDownloadConfirmation = false
    @State private var localRefreshTrigger = 0
    @State private var toast: ToastData?
    @State private var loadTask: Task<Void, Never>?

    private var downloadQueue: DownloadQueueManager { .shared }

    struct ComicSession: Identifiable, Equatable {
        var id: String { source.id }
        let source: any ComicSource
        
        static func == (lhs: ComicSession, rhs: ComicSession) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        NavigationStack {
            mainContent
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            // 背景
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            contentLayer

            // ダウンロードキュープログレスバナー
            if downloadQueue.isActive {
                VStack {
                    Spacer()
                    downloadQueueBanner
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
            libraryViewModel.isOfflineMode = authViewModel.isOfflineMode
            libraryViewModel.configure(with: authViewModel.authorizer)
            downloadQueue.configure(
                driveService: libraryViewModel.driveService,
                authorizer: authViewModel.authorizer,
                accessToken: authViewModel.accessToken,
                refreshAccessToken: { await authViewModel.refreshedAccessToken() }
            )
            downloadQueue.onTaskFinished = { _ in
                libraryViewModel.refreshDownloadedComics()
            }
            downloadQueue.onSeriesThumbnailUpdated = { folderId in
                // 実際にディスクへのサムネイル生成が完了したタイミングで前段キャッシュを無効化し、
                // 次回表示時に新しいファイルを拾わせる
                libraryViewModel.invalidateSeriesThumbnail(folderId: folderId)
            }
            downloadQueue.onQueueDrained = { completed, failed in
                guard completed + failed > 0 else { return }
                if failed == 0 {
                    toast = ToastData(
                        title: "ダウンロード完了",
                        message: "\(completed)件のダウンロードが完了しました",
                        type: .success
                    )
                } else {
                    toast = ToastData(
                        title: "ダウンロード完了 (\(failed)件失敗)",
                        message: "\(completed)件完了、\(failed)件失敗しました",
                        type: .error
                    )
                }
            }
            await libraryViewModel.loadFiles()
        }
        .onChange(of: authViewModel.isOfflineMode) { _, newValue in
            loadTask?.cancel()
            libraryViewModel.isOfflineMode = newValue
            loadTask = Task {
                await libraryViewModel.loadFiles()
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            if newValue == nil {
                localRefreshTrigger += 1
            }
        }
        .onChange(of: readingSession) { _, newValue in
            if newValue == nil {
                libraryViewModel.refreshDownloadedComics()
            }
        }
        .modifier(AlertsAndSheetsModifier(
            showingSignOutAlert: $showingSignOutAlert,
            showingBulkDownloadConfirmation: $showingBulkDownloadConfirmation,
            selectedItem: $selectedItem,
            selectedFolderForBulk: $selectedFolderForBulk,
            showingCascadeDownloadConfirmation: $showingCascadeDownloadConfirmation,
            selectedItemForCascade: $selectedItemForCascade,
            showingTrialDownloadConfirmation: $showingTrialDownloadConfirmation,
            showingDownloadQueue: $showingDownloadQueue,
            readingSession: $readingSession,
            toast: $toast,
            authViewModel: authViewModel,
            libraryViewModel: libraryViewModel
        ))
    }
    
    @ViewBuilder
    private var contentLayer: some View {
        VStack(spacing: 0) {
            offlineHeaderView
            
            if libraryViewModel.isLoading && libraryViewModel.items.isEmpty {
                shimmerLoadingView
            } else if let error = libraryViewModel.errorMessage {
                errorView(message: error)
            } else if libraryViewModel.items.isEmpty {
                emptyView
            } else {
                fileListContent
            }
        }
    }
    

    // MARK: - Subviews
    
    /// ファイル一覧コンテンツ
    @ViewBuilder
    private var fileListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                recommendationSection
                
                // パンくずリスト
                if !libraryViewModel.folderPath.isEmpty {
                    breadcrumbView
                }
                
                itemsSection
                
                // さらに読み込み
                if libraryViewModel.hasMoreItems {
                    autoLoadMoreView
                }
            }
            .padding()
        }
    }
    
    /// おすすめセクション
    @ViewBuilder
    private var recommendationSection: some View {
        if libraryViewModel.folderPath.isEmpty {
            if !libraryViewModel.nextRecommendedComics.isEmpty {
                RecentComicsShelfView(
                    title: "続きを読みませんか？",
                    readingSession: $readingSession,
                    recentComics: libraryViewModel.nextRecommendedComics
                )
                .padding(.bottom, 8)
            }
            
            if !libraryViewModel.recentComics.isEmpty {
                RecentComicsShelfView(
                    title: "最近読んだ作品",
                    readingSession: $readingSession,
                    recentComics: libraryViewModel.recentComics
                )
                Divider().padding(.vertical, 8)
            }
        }
    }
    
    /// アイテム一覧セクション
    @ViewBuilder
    private var itemsSection: some View {
        switch libraryViewModel.viewMode {
        case .grid:
            DriveItemGridView(
                gridColumns: gridColumns,
                libraryViewModel: libraryViewModel,
                onItemTap: handleItemTap,
                onBulkDownload: handleBulkDownload,
                onDownloadSingle: handleDownloadSingle,
                onDownloadFrom: handleDownloadFrom
            )
        case .list:
            DriveItemListView(
                libraryViewModel: libraryViewModel,
                onItemTap: handleItemTap,
                onBulkDownload: handleBulkDownload,
                onDownloadSingle: handleDownloadSingle,
                onDownloadFrom: handleDownloadFrom
            )
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
            .onAppear {
                if libraryViewModel.hasMoreItems && !libraryViewModel.isLoading {
                    Task { await libraryViewModel.loadMoreFiles() }
                }
            }
    }
    
    /// オフライン制御ヘッダー（インジケータとトグルスイッチ）
    private var offlineHeaderView: some View {
        VStack(spacing: 0) {
            if authViewModel.isOfflineMode {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("オフラインモード")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                    Text("ダウンロード済みのみ表示")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.orange)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            HStack {
                Label {
                    Text("オフラインモード")
                        .font(.body)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: authViewModel.isOfflineMode ? "wifi.slash" : "wifi")
                        .foregroundColor(authViewModel.isOfflineMode ? .orange : .blue)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { authViewModel.isOfflineMode },
                    set: { newValue in
                        withAnimation {
                            authViewModel.isOfflineMode = newValue
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .orange))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground))
            
            Divider()
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
    
    /// ダウンロードキューバナー（タップで一覧表示）
    private var downloadQueueBanner: some View {
        HStack(spacing: 16) {
            ProgressView()
                .tint(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("バックグラウンドダウンロード中...")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                HStack {
                    ProgressView(value: downloadQueue.overallProgress)
                        .progressViewStyle(.linear)
                        .tint(.green)

                    Text("\(downloadQueue.finishedCount) / \(downloadQueue.totalCount)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Image(systemName: "chevron.up")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding()
        .shadow(radius: 10)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDownloadQueue = true
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: downloadQueue.isActive)
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

                // 試し読み（ルート表示時のみ）
                if libraryViewModel.folderPath.isEmpty {
                    Button {
                        handleTrialDownload()
                    } label: {
                        Label("試し読み（全シリーズの1巻）", systemImage: "sparkles")
                    }
                }

                // ダウンロード一覧
                Button {
                    showingDownloadQueue = true
                } label: {
                    Label("ダウンロード", systemImage: "arrow.down.circle")
                }

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

    /// オフラインモード時にダウンロード操作をブロックし、案内トーストを表示
    private func blockIfOffline() -> Bool {
        guard authViewModel.isOfflineMode else { return false }
        toast = ToastData(
            title: "オフラインモード",
            message: "オフライン中はダウンロードできません。",
            type: .error
        )
        return true
    }

    /// フォルダ長押し: シリーズ一括ダウンロードの確認
    private func handleBulkDownload(_ folder: DriveItem) {
        guard !blockIfOffline() else { return }
        selectedFolderForBulk = folder
        showingBulkDownloadConfirmation = true
    }

    /// 巻の長押し: この巻のみダウンロード（即キュー追加）
    private func handleDownloadSingle(_ item: DriveItem) {
        guard !blockIfOffline() else { return }
        // 既にキュー中の場合はenqueueが既存タスクを返すため、事前にチェックして
        // 「追加しました」という誤解を招くトーストが出ないようにする
        let alreadyQueued = downloadQueue.isInQueue(driveFileId: item.id)
        if downloadQueue.enqueue(.file(item)) != nil && !alreadyQueued {
            toast = ToastData(
                title: "ダウンロード開始",
                message: "\(item.name) をキューに追加しました",
                type: .info
            )
        }
    }

    /// 巻の長押し: この巻以降をダウンロードの確認
    private func handleDownloadFrom(_ item: DriveItem) {
        guard !blockIfOffline() else { return }
        selectedItemForCascade = item
        showingCascadeDownloadConfirmation = true
    }

    /// メニュー: 試し読み（全シリーズの1巻をダウンロード）の確認
    private func handleTrialDownload() {
        guard !blockIfOffline() else { return }
        guard !downloadQueue.isTrialEnqueueInProgress else {
            toast = ToastData(
                title: "試し読みダウンロード",
                message: "現在処理中です。しばらくお待ちください。",
                type: .info
            )
            return
        }
        showingTrialDownloadConfirmation = true
    }

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
                if authViewModel.isOfflineMode {
                    toast = ToastData(
                        title: "オフラインモード",
                        message: "この漫画はオフラインでは閲覧できません。",
                        type: .error
                    )
                } else {
                    selectedItem = item
                }
            }
        } else if item.isImage {
            // 画像ファイルはストリーミング閲覧開始
            if authViewModel.isOfflineMode {
                toast = ToastData(
                    title: "オフラインモード",
                    message: "この漫画はオフラインでは閲覧できません。",
                    type: .error
                )
            } else {
                startStreamingRead(from: item)
            }
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
            driveService: libraryViewModel.driveService,
            parentId: libraryViewModel.folderPath.dropLast().last?.id
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
    let seriesThumbnailURL: URL?

    private var isDownloaded: Bool { localComic != nil }
    private var localThumbnailURL: URL? { localComic?.imagePaths.first }
    private var readingProgress: Double { localComic?.readingProgress ?? 0.0 }

    var body: some View {
        VStack(spacing: 8) {
            // サムネイル / アイコン
            // 正方形の背景をレイアウトの基準とし、画像はoverlayで重ねてクリップする
            // （scaledToFillはframe制約なしだと横長画像でレイアウトがセル外へ広がり、
            //   隣のセルに被ってしまうため）
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    thumbnailContent
                }
                .overlay {
                    // 読了プログレスバー
                    if isDownloaded && readingProgress > 0 {
                        VStack {
                            Spacer()
                            ProgressView(value: readingProgress)
                                .progressViewStyle(.linear)
                                .tint(.blue)
                                .background(Color.white.opacity(0.8))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

    /// サムネイル画像（優先順: ファイル自身のDriveサムネ → ローカル1ページ目 → シリーズサムネ → アイコン）
    /// はみ出しのクリップは呼び出し側（正方形背景のoverlay + clipShape）で行う
    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailURL = item.thumbnailURL {
            KFImage(thumbnailURL)
                .resizable()
                .scaledToFill()
        } else if let localThumbnailURL = localThumbnailURL {
            KFImage(localThumbnailURL)
                .resizable()
                .scaledToFill()
        } else if item.isFolder, let seriesThumbnailURL = seriesThumbnailURL {
            // シリーズ（1巻）の永続サムネイル
            KFImage(seriesThumbnailURL)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: item.iconName)
                .font(.system(size: 40))
                .foregroundColor(iconColor)
        }
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
    let seriesThumbnailURL: URL?

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
                } else if item.isFolder, let seriesThumbnailURL = seriesThumbnailURL {
                    // シリーズ（1巻）の永続サムネイル
                    KFImage(seriesThumbnailURL)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
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

// MARK: - View Modifiers

struct AlertsAndSheetsModifier: ViewModifier {
    @Binding var showingSignOutAlert: Bool
    @Binding var showingBulkDownloadConfirmation: Bool
    @Binding var selectedItem: DriveItem?
    @Binding var selectedFolderForBulk: DriveItem?
    @Binding var showingCascadeDownloadConfirmation: Bool
    @Binding var selectedItemForCascade: DriveItem?
    @Binding var showingTrialDownloadConfirmation: Bool
    @Binding var showingDownloadQueue: Bool
    @Binding var readingSession: LibraryView.ComicSession?
    @Binding var toast: ToastData?

    let authViewModel: AuthViewModel
    let libraryViewModel: LibraryViewModel

    /// 「次のDriveアイテムを開く」処理の最新リクエストを追跡するトークン
    /// 0.6秒の遅延やフォルダ内一覧取得中に別の遷移リクエストが割り込んだ場合、
    /// 古いリクエストがreadingSessionを上書きしてしまうのを防ぐために使う
    @State private var pendingOpenNextDriveItemID: String?

    /// リーダーからの「次のDriveアイテムを開く」通知を処理する
    private func handleOpenNextDriveItem(_ nextItem: DriveItem) {
        // 通知受信時点でリクエストIDと現在のフォルダIDをスナップショットする
        // （遅延中にフォルダ移動やさらに新しい遷移が発生しても影響を受けないようにするため）
        let requestID = nextItem.id
        let parentId = libraryViewModel.currentFolderId
        pendingOpenNextDriveItemID = requestID

        // 現在のセッションを閉じる
        readingSession = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // この間に別のリクエストが割り込んでいたら何もしない
            guard pendingOpenNextDriveItemID == requestID, readingSession == nil else { return }

            if authViewModel.isOfflineMode {
                openNextDriveItemOffline(nextItem)
            } else {
                openNextDriveItemOnline(nextItem, requestID: requestID, parentId: parentId)
            }
        }
    }

    /// オフラインモード時: ダウンロード済みアーカイブのみ開ける
    private func openNextDriveItemOffline(_ nextItem: DriveItem) {
        if nextItem.isArchive,
           var existingComic = try? LocalStorageService.shared.findComic(byDriveFileId: nextItem.id),
           existingComic.status == .completed {
            // 次の巻は1ページ目から表示する
            existingComic.lastReadPage = 0
            readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: existingComic))
        } else {
            // 未ダウンロードのアーカイブ、またはフォルダ/画像はオフライン表示不可
            toast = ToastData(
                title: "オフラインモード",
                message: "この漫画はオフラインでは閲覧できません。",
                type: .error
            )
        }
    }

    /// オンライン時: アイテムの種類に応じてソースを構築する
    private func openNextDriveItemOnline(_ nextItem: DriveItem, requestID: String, parentId: String?) {
        if nextItem.isFolder {
            openNextFolder(nextItem, requestID: requestID, parentId: parentId)
        } else if nextItem.isImage {
            openNextImage(nextItem, parentId: parentId)
        } else if nextItem.isArchive {
            openNextArchive(nextItem)
        }
    }

    /// 次の巻がフォルダ（画像ストリーミング）の場合
    private func openNextFolder(_ nextItem: DriveItem, requestID: String, parentId: String?) {
        // フォルダ内の画像一覧を取得してからソースを構築する
        // （空のfilesを渡すとpageCount=0のまま固定されてしまうため）
        Task { @MainActor in
            var allItems: [DriveItem] = []
            var token: String?
            do {
                repeat {
                    let result = try await libraryViewModel.driveService.listFiles(
                        in: nextItem.id,
                        pageToken: token
                    )
                    allItems.append(contentsOf: result.items)
                    token = result.nextPageToken
                } while token != nil
            } catch {
                toast = ToastData(
                    title: "読み込み失敗",
                    message: error.localizedDescription,
                    type: .error
                )
                return
            }

            let images = allItems.filter { $0.isImage }
            guard !images.isEmpty else {
                toast = ToastData(
                    title: "ダウンロード",
                    message: "この巻には画像が含まれていません",
                    type: .error
                )
                return
            }

            // 取得中に別の遷移リクエストが割り込んでいた場合は、それを上書きしない
            guard pendingOpenNextDriveItemID == requestID, readingSession == nil else { return }

            let source = RemoteComicSource(
                folderId: nextItem.id,
                title: nextItem.name,
                files: images,
                driveService: libraryViewModel.driveService,
                parentId: parentId
            )
            readingSession = LibraryView.ComicSession(source: source)
        }
    }

    /// 次の巻が単独画像の場合
    private func openNextImage(_ nextItem: DriveItem, parentId: String?) {
        // idは画像自身のものを使う（親フォルダIDを使うと、同じフォルダ内の
        // 別画像へ連続ジャンプした際にidが変化せず、状態リセットも次巻検出も機能しなくなる）
        let source = RemoteComicSource(
            folderId: nextItem.id,
            title: nextItem.name,
            files: [nextItem],
            driveService: libraryViewModel.driveService,
            parentId: parentId
        )
        readingSession = LibraryView.ComicSession(source: source)
    }

    /// 次の巻がアーカイブの場合
    private func openNextArchive(_ nextItem: DriveItem) {
        // アーカイブの場合はダウンロード済みかチェック
        if var existingComic = try? LocalStorageService.shared.findComic(byDriveFileId: nextItem.id),
           existingComic.status == .completed {
            // 次の巻は1ページ目から表示する
            existingComic.lastReadPage = 0
            readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: existingComic))
        } else {
            // 未ダウンロードの場合は、本来はDownloadSheetを出すべきだが
            // リーダーからの自動遷移なので、一旦選択状態にする
            selectedItem = nextItem
        }
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AllComicsDeleted"))) { _ in
                // ストレージ管理画面での全削除を反映する（downloadedComics/seriesThumbnailsの
                // 前段キャッシュが削除済みファイルのURLを保持し続けないようにする）
                libraryViewModel.refreshDownloadedComics()
                libraryViewModel.invalidateAllSeriesThumbnails()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNextVolume"))) { notification in
                if var nextComic = notification.object as? LocalComic {
                    // 次の巻は1ページ目から表示する
                    nextComic.lastReadPage = 0

                    // 現在のセッションを一度閉じてから新しいセッションを開く
                    readingSession = nil
                    
                    // 確実に前のシートが閉じるのを待ってから新しいセッションを開始
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: nextComic))
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNextDriveItem"))) { notification in
                if let nextItem = notification.object as? DriveItem {
                    handleOpenNextDriveItem(nextItem)
                }
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
                    guard let folder = selectedFolderForBulk else { return }
                    Task { @MainActor in
                        do {
                            let added = try await DownloadQueueManager.shared.enqueueSeries(folder: folder)
                            if added > 0 {
                                toast = ToastData(
                                    title: "ダウンロード開始",
                                    message: "\(folder.name) の\(added)件をキューに追加しました",
                                    type: .info
                                )
                            } else {
                                toast = ToastData(
                                    title: "ダウンロード",
                                    message: "追加できるファイルがありません（ダウンロード済み）",
                                    type: .info
                                )
                            }
                        } catch {
                            toast = ToastData(
                                title: "ダウンロード失敗",
                                message: error.localizedDescription,
                                type: .error
                            )
                        }
                    }
                }
            } message: {
                if let folder = selectedFolderForBulk {
                    Text("\(folder.name)内のアーカイブをバックグラウンドで一括ダウンロードします。")
                }
            }
            .alert("この巻以降をダウンロード", isPresented: $showingCascadeDownloadConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ダウンロード") {
                    guard let item = selectedItemForCascade,
                          let folderId = libraryViewModel.currentFolderId else { return }
                    Task { @MainActor in
                        do {
                            let (added, total) = try await DownloadQueueManager.shared.enqueueFrom(
                                folderId: folderId,
                                item: item
                            )
                            if added > 0 {
                                toast = ToastData(
                                    title: "ダウンロード開始",
                                    message: "\(item.name)以降の\(added)件をキューに追加しました",
                                    type: .info
                                )
                            } else if total > 0 {
                                toast = ToastData(
                                    title: "ダウンロード",
                                    message: "追加できるファイルがありません（ダウンロード済み）",
                                    type: .info
                                )
                            } else {
                                toast = ToastData(
                                    title: "ダウンロード失敗",
                                    message: "対象の巻が見つかりませんでした",
                                    type: .error
                                )
                            }
                        } catch {
                            toast = ToastData(
                                title: "ダウンロード失敗",
                                message: error.localizedDescription,
                                type: .error
                            )
                        }
                    }
                }
            } message: {
                if let item = selectedItemForCascade {
                    Text("「\(item.name)」以降のアーカイブをバックグラウンドでダウンロードします。")
                }
            }
            .alert("試し読みダウンロード", isPresented: $showingTrialDownloadConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ダウンロード") {
                    Task { @MainActor in
                        do {
                            let (added, seriesCount, candidateCount) =
                                try await DownloadQueueManager.shared.enqueueTrialVolumes()
                            if added > 0 {
                                toast = ToastData(
                                    title: "ダウンロード開始",
                                    message: "\(seriesCount)シリーズ中\(added)件の1巻をキューに追加しました",
                                    type: .info
                                )
                            } else if candidateCount > 0 {
                                toast = ToastData(
                                    title: "ダウンロード",
                                    message: "追加できるファイルがありません（ダウンロード済み）",
                                    type: .info
                                )
                            } else if seriesCount > 0 {
                                toast = ToastData(
                                    title: "ダウンロード",
                                    message: "対象のアーカイブが見つかりませんでした",
                                    type: .error
                                )
                            } else {
                                toast = ToastData(
                                    title: "ダウンロード",
                                    message: "シリーズフォルダが見つかりませんでした",
                                    type: .info
                                )
                            }
                        } catch {
                            toast = ToastData(
                                title: "ダウンロード失敗",
                                message: error.localizedDescription,
                                type: .error
                            )
                        }
                    }
                }
            } message: {
                Text("全シリーズの1巻をバックグラウンドで一括ダウンロードします。シリーズ数が多い場合は時間がかかることがあります。")
            }
            .sheet(isPresented: $showingDownloadQueue) {
                DownloadQueueView()
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
                        readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: comic))
                    }
                )
            }
            .fullScreenCover(item: $readingSession) { session in
                // sessionのidが変わるたびにReaderViewとその@State（ReaderViewModel）を
                // 強制的に作り直す。これがないと、次の巻への遷移がSwiftUI側で
                // 「新規表示」ではなく「同一シートの内容差し替え」として扱われた場合に
                // 古いReaderViewModel（＝古いページ数）が使い回されてしまう
                ReaderView(source: session.source)
                    .id(session.id)
            }
    }
}
