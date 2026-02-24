// StorageManagementView.swift
// GD-MangaReader
//
// ストレージ管理画面

import SwiftUI

struct StorageManagementView: View {
    @State private var viewModel = StorageViewModel()
    @State private var showingDeleteAllAlert = false
    
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
                            Task {
                                await viewModel.deleteCompletedComics()
                            }
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
            Section("ダウンロード済みアイテム") {
                if viewModel.comics.isEmpty && !viewModel.isLoading {
                    Text("ダウンロードされたデータはありません")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.comics) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(item.formattedSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await viewModel.deleteComic(viewModel.comics[index])
                            }
                        }
                    }
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
    }
}

#Preview {
    NavigationStack {
        StorageManagementView()
    }
}
