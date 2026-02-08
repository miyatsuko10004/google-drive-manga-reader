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
    @State private var showingDownloadSheet = false
    @State private var readingSession: ComicSession?
    
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
                    ProgressView("読み込み中...")
                        .scaleEffect(1.2)
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
            }
            .navigationTitle(libraryViewModel.currentFolderName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                toolbarContent
            }
            .refreshable {
                await libraryViewModel.refresh()
            }
            .task {
                await libraryViewModel.configure(with: authViewModel.authorizer)
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
            .sheet(isPresented: $showingDownloadSheet) {
                if let item = selectedItem {
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
                        isPresented: $showingDownloadSheet,
                        onComplete: { comic in
                            // ローカルコミックとして開く
                            readingSession = ComicSession(source: LocalComicSource(comic: comic))
                        }
                    )
                }
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
                // パンくずリスト
                if !libraryViewModel.folderPath.isEmpty {
                    breadcrumbView
                }
                
                // アイテム一覧
                switch libraryViewModel.viewMode {
                case .grid:
                    gridView
                case .list:
                    listView
                }
                
                // さらに読み込み
                if libraryViewModel.hasMoreItems {
                    loadMoreButton
                }
            }
            .padding()
        }
    }
    
    /// グリッド表示
    private var gridView: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(libraryViewModel.items) { item in
                DriveItemGridCell(item: item)
                    .onTapGesture {
                        handleItemTap(item)
                    }
            }
        }
    }
    
    /// リスト表示
    private var listView: some View {
        LazyVStack(spacing: 8) {
            ForEach(libraryViewModel.items) { item in
                DriveItemListRow(item: item)
                    .onTapGesture {
                        handleItemTap(item)
                    }
            }
        }
    }
    
    /// パンくずリスト
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
    
    /// さらに読み込みボタン
    private var loadMoreButton: some View {
        Button {
            Task { await libraryViewModel.loadMoreFiles() }
        } label: {
            if libraryViewModel.isLoading {
                ProgressView()
            } else {
                Text("さらに読み込む")
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
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
            // アーカイブファイルはダウンロード
            selectedItem = item
            showingDownloadSheet = true
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
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: 40))
                        .foregroundColor(iconColor)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
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
    
    var body: some View {
        HStack(spacing: 12) {
            // アイコン
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 44, height: 44)
                
                Image(systemName: item.iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
            }
            
            // ファイル情報
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                
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
