// StorageManagementView.swift
// GD-MangaReader
//
// ストレージ管理画面

import SwiftUI

struct StorageManagementView: View {
    @Environment(StatusCenter.self) private var statusCenter
    @State private var viewModel = StorageViewModel()
    @State private var showingDeleteAllAlert = false
    @State private var showingDeleteCompletedAlert = false

    /// スワイプ削除の確認待ちアイテム（非nilで確認ダイアログを表示）
    @State private var itemPendingDeletion: StorageViewModel.ComicStorageItem?

    /// リーダーで開いているコミック（非nilでfullScreenCover表示）
    @State private var readingComic: LocalComic?

    var body: some View {
        List {
            // 概要セクション
            Section {
                HStack {
                    Text("総使用量")
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text(viewModel.formattedTotalUsage)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !viewModel.comics.isEmpty {
                    // 読了済み削除ボタン
                    let completedCount = viewModel.comics.filter { $0.localComic.readingProgress >= 1.0 }.count
                    if completedCount > 0 {
                        Button(role: .destructive) {
                            showingDeleteCompletedAlert = true
                        } label: {
                            Label("読了済みのデータを削除 (\(completedCount)件)", systemImage: "trash")
                        }
                    }
                    
                    // 全削除ボタン
                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        Label("すべてのデータを削除", systemImage: "trash")
                    }
                }
            } footer: {
                Text("ダウンロードした漫画データを管理できます。削除してもGoogle Drive上のデータは消えません。")
            }
            
            // アイテムリスト
            Section {
                if viewModel.comics.isEmpty && !viewModel.isLoading {
                    Text("ダウンロードされたデータはありません")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.comics) { item in
                        // 行タップでリーダーを開く
                        Button {
                            readingComic = item.localComic
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                        .font(.body)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                    Text(item.formattedSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .onDelete { indexSet in
                        // ファイル削除は元に戻せないため、即削除せず確認ダイアログを挟む
                        guard let index = indexSet.first, index < viewModel.comics.count else { return }
                        itemPendingDeletion = viewModel.comics[index]
                    }
                }
            } header: {
                HStack {
                    Text("ダウンロード済みアイテム")
                    Spacer()
                    // ソート切り替えメニュー
                    Menu {
                        Picker("並び替え", selection: Binding(
                            get: { viewModel.sortOption },
                            set: { viewModel.sortOption = $0 }
                        )) {
                            ForEach(StorageViewModel.SortOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.arrow.down")
                                .accessibilityHidden(true)
                            Text(viewModel.sortOption.label)
                        }
                        .font(.caption)
                    }
                    .accessibilityLabel("並び替え: \(viewModel.sortOption.label)")
                }
            }
        }
        .navigationTitle("ストレージ管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
        .refreshable {
            await viewModel.loadData()
        }
        .alert("すべてのデータを削除", isPresented: $showingDeleteAllAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    await viewModel.deleteAll()
                }
            }
        } message: {
            Text("ダウンロード済みの漫画データをすべて削除しますか？\nこの操作は取り消せません。")
        }
        .alert("読了済みのデータを削除", isPresented: $showingDeleteCompletedAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    await viewModel.deleteCompletedComics()
                }
            }
        } message: {
            let count = viewModel.comics.filter { $0.localComic.readingProgress >= 1.0 }.count
            Text("読了済みの漫画データ(\(count)件)を削除しますか？\nこの操作は取り消せません。")
        }
        // スワイプ削除の確認（ファイル削除は元に戻せないため必ず確認を挟む）
        .confirmationDialog(
            "データを削除",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: itemPendingDeletion
        ) { item in
            Button("削除", role: .destructive) {
                Task {
                    await viewModel.deleteComic(item)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { item in
            Text("「\(item.title)」を削除しますか？\n削除したデータは元に戻せません。")
        }
        // 行タップでダウンロード済みコミックをリーダーで開く
        // （この画面はLibraryViewのNavigationStack内にpushされるため、ローカルのfullScreenCoverで表示する）
        .fullScreenCover(item: $readingComic) { comic in
            ReaderView(source: LocalComicSource(comic: comic))
        }
        .onChange(of: readingComic) { _, newValue in
            // リーダーを閉じたら再読込する（読書進捗の更新や「読了後に自動削除」による
            // 削除をサイズ・件数表示へ反映するため）
            if newValue == nil {
                Task { await viewModel.loadData() }
            }
        }
        // ViewModelのエラーはStatusCenterのトーストで通知する
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard let message = newValue else { return }
            statusCenter.show(ToastData(
                title: "エラー",
                message: message,
                type: .error
            ))
            // 同じ操作を再試行して同じエラーになった場合もonChangeが発火するようクリアしておく
            viewModel.clearError()
        }
    }
}

#Preview {
    NavigationStack {
        StorageManagementView()
    }
    .environment(StatusCenter.shared)
}
