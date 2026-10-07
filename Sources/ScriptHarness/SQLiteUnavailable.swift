// SQLiteUnavailable.swift
// ScriptHarness
//
// WASI has no SQLite3 module, so Package.swift excludes BREPGraphSQLiteExporter.swift from the
// WASI build. This stands in for it: same public surface, and the export fails with a clear error.

#if os(WASI)
    import Foundation
    import OCCTSwift

    /// Stand-in for the SQLite exporter on platforms without the system SQLite3 module.
    public enum BREPGraphSQLiteExporter {
        /// Always throws `SQLiteExportError.unavailable`.
        public static func export(_ graph: BRepGraph, to url: URL, description: String? = nil)
            throws
        {
            throw SQLiteExportError.unavailable
        }
    }

    public enum SQLiteExportError: Error, LocalizedError {
        // Same cases as the real enum in BREPGraphSQLiteExporter.swift, so a caller that matches on
        // them compiles on both; only `unavailable` is ever thrown here.
        case cannotOpen(String)
        case prepareFailed
        case execFailed(String)
        case unavailable

        public var errorDescription: String? {
            switch self {
            case .cannotOpen(let path): return "Cannot open SQLite database at \(path)"
            case .prepareFailed: return "Failed to prepare SQLite statement"
            case .execFailed(let msg): return "SQLite exec failed: \(msg)"
            case .unavailable: return "SQLite export is not available on this platform"
            }
        }
    }
#endif
