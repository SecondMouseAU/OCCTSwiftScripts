// ManifestIO.swift
// ScriptHarness
//
// Atomic manifest writes, the merge `occtkit import` and `load-brep` use to add bodies to an
// existing scene, and the failure marker a host reads to tell a failed run from an empty one.

import Foundation

/// Reads and writes `manifest.json` so a reader never sees a half-written file.
public enum ManifestIO {
    public static let manifestFilename = "manifest.json"

    /// File a failed run leaves beside the manifest.
    ///
    /// A successful `emit()` removes it.
    public static let failureMarkerFilename = "run-failed.json"

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Replaces the manifest at `url` atomically: the data goes to a temporary file in the same
    /// directory, then is renamed over the destination.
    public static func write(_ manifest: ScriptManifest, to url: URL) throws {
        try encoder().encode(manifest).write(to: url, options: .atomic)
    }

    /// Merges the bodies and graphs of a manifest into the one already on disk.
    ///
    /// With no manifest there it writes `manifest` as is.
    ///
    /// An existing body or graph with the same `id` (or, lacking one, the same `file`) is replaced
    /// in place; every other entry stays. Manifest-level fields already present (`description`,
    /// `metadata`, and any key this version does not know) are kept, and only `timestamp` is
    /// refreshed. The merge works on the raw JSON so a host's own keys survive a round trip.
    ///
    /// - Throws: if the existing file is not a JSON object, rather than overwriting it.
    public static func merge(_ manifest: ScriptManifest, into url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try write(manifest, to: url)
            return
        }

        guard
            let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any],
            let incoming = try JSONSerialization.jsonObject(with: encoder().encode(manifest))
                as? [String: Any]
        else {
            throw ScriptError.message("\(url.path) is not a JSON object; refusing to overwrite it")
        }

        var merged = existing
        merged["timestamp"] = incoming["timestamp"]
        for key in ["version", "description", "metadata"] where merged[key] == nil {
            merged[key] = incoming[key]
        }
        for key in ["bodies", "graphs"] {
            let combined = mergeEntries(
                existing: existing[key] as? [[String: Any]] ?? [],
                incoming: incoming[key] as? [[String: Any]] ?? [])
            if !combined.isEmpty { merged[key] = combined }
        }

        let data = try JSONSerialization.data(
            withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func mergeEntries(
        existing: [[String: Any]], incoming: [[String: Any]]
    ) -> [[String: Any]] {
        func identity(_ entry: [String: Any]) -> String? {
            (entry["id"] as? String) ?? (entry["file"] as? String)
        }
        var result = existing
        for entry in incoming {
            if let key = identity(entry),
                let at = result.firstIndex(where: { identity($0) == key })
            {
                result[at] = entry
            } else {
                result.append(entry)
            }
        }
        return result
    }

    /// Records that a run failed, atomically, so a host can report it instead of inferring it
    /// from a manifest that looks empty.
    public static func writeFailureMarker(message: String, in directory: URL) throws {
        struct Marker: Encodable {
            let version = 1
            let timestamp = Date()
            let message: String
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder().encode(Marker(message: message))
            .write(
                to: directory.appendingPathComponent(failureMarkerFilename), options: .atomic)
    }

    public static func clearFailureMarker(in directory: URL) {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(failureMarkerFilename))
    }
}
