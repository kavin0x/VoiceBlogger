import Foundation
import CryptoKit

enum ModelIntegrityChecker {
    // Computes a fingerprint of the model directory: a SHA256 over the sorted list of
    // "relative-path:file-size-in-bytes" pairs. This catches file removal, replacement,
    // and size changes without needing pre-known hashes. It does NOT protect against
    // bit-exact replacements of the same-size files, but it eliminates the symlink-only
    // and empty-directory false-positive cases.
    static func fingerprint(of directory: URL) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var entries: [(path: String, size: Int)] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            ) else { continue }

            let relative = url.path.hasPrefix(directory.path)
                ? String(url.path.dropFirst(directory.path.count))
                : url.path

            if values.isRegularFile == true, let size = values.fileSize {
                entries.append((path: relative, size: size))
            } else if values.isSymbolicLink == true {
                // Resolve the symlink and use the real file's size so HuggingFace Hub
                // caches (which store files as symlinks into a blobs/ directory) are
                // included in the fingerprint.
                let resolved = url.resolvingSymlinksInPath()
                if let resolvedValues = try? resolved.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                ), resolvedValues.isRegularFile == true, let resolvedSize = resolvedValues.fileSize {
                    entries.append((path: relative, size: resolvedSize))
                }
            }
        }

        guard !entries.isEmpty else { return nil }

        let sorted = entries.sorted { $0.path < $1.path }
        let payload = sorted.map { "\($0.path):\($0.size)" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func store(fingerprint: String, forKey key: String) {
        UserDefaults.standard.set(fingerprint, forKey: key)
    }

    static func verify(directory: URL, storedKey key: String) -> Bool {
        // A directory without a completion fingerprint may be a partially downloaded
        // snapshot left behind by process termination. Never establish trust from the
        // files being verified; only a completed load/download may store the baseline.
        guard let stored = UserDefaults.standard.string(forKey: key) else { return false }
        guard let current = fingerprint(of: directory) else { return false }
        return current == stored
    }

    static func invalidate(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
