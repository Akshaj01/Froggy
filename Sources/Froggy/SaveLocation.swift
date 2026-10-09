import Foundation

@MainActor
enum SaveLocation {
    static var defaults: UserDefaults = .standard

    private static let key = "saveFolderPath"

    static var folder: URL {
        if let path = defaults.string(forKey: key) {
            let chosen = URL(fileURLWithPath: path, isDirectory: true)
            if prepare(chosen) {
                return chosen
            }
        }
        let fallback = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Froggy", isDirectory: true)
        _ = prepare(fallback)
        defaults.set(fallback.path, forKey: key)
        return fallback
    }

    static func setFolder(_ url: URL) {
        _ = prepare(url)
        defaults.set(url.path, forKey: key)
    }

    static var displayPath: String {
        let path = folder.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
    }

    static func uniqueDestination(in folder: URL, baseName: String, pathExtension: String) -> URL {
        let clean = sanitized(baseName)
        var candidate = folder.appendingPathComponent(clean).appendingPathExtension(pathExtension)
        var index = 2
        let manager = FileManager.default
        while manager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(clean) \(index)").appendingPathExtension(pathExtension)
            index += 1
        }
        return candidate
    }

    private static func prepare(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private static func sanitized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Froggy" : trimmed
        return base.replacingOccurrences(of: "/", with: "-")
    }
}
