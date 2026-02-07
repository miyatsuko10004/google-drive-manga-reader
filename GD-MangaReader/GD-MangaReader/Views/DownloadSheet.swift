// DownloadSheet.swift
// GD-MangaReader
//
// ダウンロード進捗表示シート

import SwiftUI

/// ダウンロード進捗を表示するシート
struct DownloadSheet: View {
    let item: DriveItem
    @Binding var isPresented: Bool
    var onComplete: (LocalComic) -> Void
    
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = DownloaderViewModel()
    @State private var downloadedComic: LocalComic?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // ファイルアイコン
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: item.iconName)
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                }
                
                // ファイル名
                Text(item.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // サイズ
                Text(item.formattedSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 進捗表示
                progressView
                
                Spacer()
                
                // ボタン
                actionButtons
            }
            .padding()
            .navigationTitle("ダウンロード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                    .disabled(viewModel.isProcessing)
                }
            }
            .task {
                await viewModel.configure(with: authViewModel.authorizer)
            }
        }
    }
    
    // MARK: - Progress View
    
    @ViewBuilder
    private var progressView: some View {
        VStack(spacing: 16) {
            switch viewModel.status {
            case .pending:
                Text("ダウンロードの準備ができました")
                    .foregroundColor(.secondary)
                
            case .downloading:
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                    
                    Text("ダウンロード中... \(Int(viewModel.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case .extracting:
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.extractProgress)
                        .progressViewStyle(.linear)
                        .tint(.green)
                    
                    Text("解凍中... \(Int(viewModel.extractProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case .completed:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("完了しました！")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    if let comic = downloadedComic {
                        Text("\(comic.pageCount)ページ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
            case .failed:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("エラーが発生しました")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            switch viewModel.status {
            case .pending:
                Button {
                    startDownload()
                } label: {
                    Label("ダウンロード開始", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            case .downloading, .extracting:
                ProgressView()
                    .scaleEffect(1.2)
                
            case .completed:
                Button {
                    if let comic = downloadedComic {
                        onComplete(comic)
                        isPresented = false
                    }
                } label: {
                    Label("読み始める", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            case .failed:
                Button {
                    viewModel.reset()
                } label: {
                    Label("再試行", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    // MARK: - Actions
    
    private func startDownload() {
        Task {
            if let comic = await viewModel.downloadAndExtract(item: item) {
                downloadedComic = comic
            }
        }
    }
}

#Preview {
    DownloadSheet(
        item: .mockZipFile,
        isPresented: .constant(true),
        onComplete: { _ in }
    )
    .environment(AuthViewModel())
}
