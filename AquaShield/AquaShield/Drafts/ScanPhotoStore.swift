//
//  ScanPhotoStore.swift
//  AquaShield
//
//  Report photos for an unsaved scanner review. Lab reports can show names and addresses, so the photos
//  are kept only while the draft exists: Application Support, complete file protection, excluded from
//  backup, and deleted when the results are saved or the user starts over.
//

import UIKit

nonisolated struct ScanPhotoStore {
    let directory: URL

    /// One folder per real/demo scope, for example ".../ScanDrafts/real".
    init(scope: String, root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appending(path: "ScanDrafts", directoryHint: .isDirectory)
            .appending(path: scope, directoryHint: .isDirectory)
    }

    /// Replaces any saved photos with these pages. Returns how many were written.
    @discardableResult
    func save(_ images: [UIImage]) -> Int {
        deleteAll()
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
            try excludeFromBackup(directory)
        } catch {
            return 0
        }
        var written = 0
        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let url = fileURL(page: index)
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                try excludeFromBackup(url)
                written += 1
            } catch {
                continue
            }
        }
        return written
    }

    /// Saved pages in order. Empty if none (or if they were deleted).
    func load() -> [UIImage] {
        pageURLs().compactMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    func pageURLs() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("page-") && $0.hasSuffix(".jpg") }
            .sorted { pageNumber($0) < pageNumber($1) }
            .map { directory.appending(path: $0) }
    }

    private func fileURL(page: Int) -> URL { directory.appending(path: "page-\(page).jpg") }

    private func pageNumber(_ name: String) -> Int {
        Int(name.dropFirst("page-".count).dropLast(".jpg".count)) ?? 0
    }

    private func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
