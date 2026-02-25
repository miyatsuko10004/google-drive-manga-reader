import SwiftUI
import Kingfisher

struct RecentComicsShelfView: View {
    @Binding var readingSession: LibraryView.ComicSession?
    let recentComics: [LocalComic]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近読んだ作品")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentComics) { comic in
                        Button {
                            // クリックですぐに開く
                            readingSession = LibraryView.ComicSession(source: LocalComicSource(comic: comic))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                // サムネイル
                                ZStack(alignment: .bottomLeading) {
                                    Group {
                                        if let firstImagePath = comic.imagePaths.first {
                                            KFImage(firstImagePath)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 120, height: 160)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        } else {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.secondarySystemGroupedBackground))
                                                .frame(width: 120, height: 160)
                                                .overlay(
                                                    Image(systemName: "book.closed")
                                                        .foregroundColor(.gray)
                                                )
                                        }
                                    }
                                    
                                    // プログレスバー（画像にかぶせる）
                                    if comic.readingProgress > 0 {
                                        ProgressView(value: comic.readingProgress)
                                            .progressViewStyle(.linear)
                                            .tint(.blue)
                                            .background(Color.white.opacity(0.8))
                                            .frame(height: 4)
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                            .padding([.horizontal, .bottom], 8)
                                    }
                                }
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                
                                // タイトル
                                Text(comic.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 120, alignment: .leading)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("\(comic.title)、読了率 \(Int(comic.readingProgress * 100))パーセント")
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }
}
