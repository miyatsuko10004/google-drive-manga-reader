import Foundation

struct LocalComic {
    let id: String
    let title: String
    var lastReadAt: Date?
    var readingProgress: Double
}

func extractSeriesTitle(from title: String) -> String {
    let patterns = [
        "\\s*[\\(\\[\\{].*?[\\)\\]\\}]$", // 末尾の括弧内を除去
        "\\s*(?:vol\\.?|#|第)?\\s*\\d+(?:\\s*[巻回話])?.*$" // 巻数表記を除去
    ]

    var result = title
    for pattern in patterns {
        if let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            result = String(result[..<range.lowerBound])
        }
    }

    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? title : trimmed
}

func runOriginal(allComics: [LocalComic], recentlyRead: [LocalComic]) -> [LocalComic] {
    var recommendations: [LocalComic] = []
    var seenSeries = Set<String>()

    for comic in recentlyRead {
        let seriesTitle = extractSeriesTitle(from: comic.title)
        guard !seriesTitle.isEmpty && !seenSeries.contains(seriesTitle) else { continue }
        seenSeries.insert(seriesTitle)

        let seriesVolumes = allComics
            .filter { extractSeriesTitle(from: $0.title) == seriesTitle }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        if let currentIndex = seriesVolumes.firstIndex(where: { $0.id == comic.id }) {
            if currentIndex + 1 < seriesVolumes.count {
                let nextVol = seriesVolumes[currentIndex + 1]
                if nextVol.readingProgress < 0.95 {
                    recommendations.append(nextVol)
                }
            }
        }
    }
    return recommendations
}

func runOptimized(allComics: [LocalComic], recentlyRead: [LocalComic]) -> [LocalComic] {
    let targetSeriesTitles = Set(recentlyRead.compactMap { comic -> String? in
        let title = extractSeriesTitle(from: comic.title)
        return title.isEmpty ? nil : title
    })

    var seriesGroups: [String: [LocalComic]] = [:]
    if !targetSeriesTitles.isEmpty {
        for comic in allComics {
            let title = extractSeriesTitle(from: comic.title)
            if targetSeriesTitles.contains(title) {
                seriesGroups[title, default: []].append(comic)
            }
        }
    }

    var recommendations: [LocalComic] = []
    var seenSeries = Set<String>()

    for comic in recentlyRead {
        let seriesTitle = extractSeriesTitle(from: comic.title)
        guard !seriesTitle.isEmpty && !seenSeries.contains(seriesTitle) else { continue }
        seenSeries.insert(seriesTitle)

        let seriesVolumes = (seriesGroups[seriesTitle] ?? [])
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        if let currentIndex = seriesVolumes.firstIndex(where: { $0.id == comic.id }) {
            if currentIndex + 1 < seriesVolumes.count {
                let nextVol = seriesVolumes[currentIndex + 1]
                if nextVol.readingProgress < 0.95 {
                    recommendations.append(nextVol)
                }
            }
        }
    }
    return recommendations
}

// Generate data
var allComics: [LocalComic] = []
for i in 0..<100 {
    for j in 1...20 {
        allComics.append(LocalComic(id: "\(i)-\(j)", title: "Comic Series \(i) Vol \(j)", lastReadAt: nil, readingProgress: 0.0))
    }
}

var recentlyRead: [LocalComic] = []
for i in 0..<5 {
    recentlyRead.append(LocalComic(id: "\(i)-5", title: "Comic Series \(i) Vol 5", lastReadAt: Date(), readingProgress: 1.0))
}

let start1 = CFAbsoluteTimeGetCurrent()
for _ in 0..<100 {
    _ = runOriginal(allComics: allComics, recentlyRead: recentlyRead)
}
let end1 = CFAbsoluteTimeGetCurrent()
print(String(format: "Original time: %.4f s", end1 - start1))

let start2 = CFAbsoluteTimeGetCurrent()
for _ in 0..<100 {
    _ = runOptimized(allComics: allComics, recentlyRead: recentlyRead)
}
let end2 = CFAbsoluteTimeGetCurrent()
print(String(format: "Optimized time: %.4f s", end2 - start2))
