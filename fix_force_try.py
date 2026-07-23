import os

files = {
    "GD-MangaReader/GD-MangaReader/ViewModels/LibraryViewModel.swift": [
        ("private static let seriesTitleBracketRegex = try! NSRegularExpression(pattern: #\"\\s*[\\(\\[\\{].*?[\\)\\]\\}]$\"#, options: .caseInsensitive)",
         "private static let seriesTitleBracketRegex = try? NSRegularExpression(pattern: #\"\\s*[\\(\\[\\{].*?[\\)\\]\\}]$\"#, options: .caseInsensitive)"),
        ("private static let seriesTitleVolumeRegex = try! NSRegularExpression(pattern: #\"\\s*(?:vol\\.?|#|第)?\\s*\\d+(?:\\s*[巻回話])?.*$\"#, options: .caseInsensitive)",
         "private static let seriesTitleVolumeRegex = try? NSRegularExpression(pattern: #\"\\s*(?:vol\\.?|#|第)?\\s*\\d+(?:\\s*[巻回話])?.*$\"#, options: .caseInsensitive)"),
        ("if let match = Self.seriesTitleBracketRegex.firstMatch(in: result, range: range1),",
         "if let regex = Self.seriesTitleBracketRegex,\n           let match = regex.firstMatch(in: result, range: range1),"),
        ("if let match = Self.seriesTitleVolumeRegex.firstMatch(in: result, range: range2),",
         "if let regex = Self.seriesTitleVolumeRegex,\n           let match = regex.firstMatch(in: result, range: range2),")
    ],
    "GD-MangaReader/GD-MangaReader/Models/DriveItem.swift": [
        ("private static let volumeRegex = try! NSRegularExpression(pattern: \"第[0-9０-９]+巻$\")",
         "private static let volumeRegex = try? NSRegularExpression(pattern: \"第[0-9０-９]+巻$\")"),
        ("if let match = Self.volumeRegex.firstMatch(in: working, range: nsRange),",
         "if let regex = Self.volumeRegex,\n           let match = regex.firstMatch(in: working, range: nsRange),")
    ],
    "GD-MangaReader/GD-MangaReader/Views/ReaderView.swift": [
        ("private static let nextVolumePrefixRegex = try! NSRegularExpression(pattern: \"(\\\\s*第?\\\\d+[巻]?|\\\\s*Vol\\\\.?\\\\s*\\\\d+|\\\\s*\\\\(\\\\d+\\\\)|\\\\s+\\\\d+)$\", options: .caseInsensitive)",
         "private static let nextVolumePrefixRegex = try? NSRegularExpression(pattern: \"(\\\\s*第?\\\\d+[巻]?|\\\\s*Vol\\\\.?\\\\s*\\\\d+|\\\\s*\\\\(\\\\d+\\\\)|\\\\s+\\\\d+)$\", options: .caseInsensitive)"),
        ("let prefix = Self.nextVolumePrefixRegex.stringByReplacingMatches(in: currentTitle, range: NSRange(currentTitle.startIndex..., in: currentTitle), withTemplate: \"\")",
         "let prefix = Self.nextVolumePrefixRegex?.stringByReplacingMatches(in: currentTitle, range: NSRange(currentTitle.startIndex..., in: currentTitle), withTemplate: \"\") ?? currentTitle")
    ]
}

for file_path, replacements in files.items():
    with open(file_path, "r") as f:
        content = f.read()

    for old, new in replacements:
        content = content.replace(old, new)

    with open(file_path, "w") as f:
        f.write(content)
