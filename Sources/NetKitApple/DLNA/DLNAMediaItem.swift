#if canImport(Network)
import Foundation

/// A media item exposed via DLNA Content Directory.
public struct DLNAMediaItem: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let creator: String?
    public let duration: TimeInterval?
    public let filePath: String
    public let thumbnailPath: String?
    public let mimeType: String
    public let fileSize: Int64?
    /// App-specific metadata served via sidecar JSON endpoint (`/media/{id}/metadata.json`).
    /// Keys and values must be JSON-serializable strings.
    public let metadata: [String: String]

    public init(
        id: String,
        title: String,
        creator: String? = nil,
        duration: TimeInterval? = nil,
        filePath: String,
        thumbnailPath: String? = nil,
        mimeType: String = "video/mp4",
        fileSize: Int64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.creator = creator
        self.duration = duration
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.metadata = metadata
    }
}

extension DLNAMediaItem {
    /// Format duration as HH:MM:SS for DIDL-Lite.
    var formattedDuration: String? {
        guard let duration else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// File extension derived from mimeType.
    var fileExtension: String {
        switch mimeType {
        case "video/mp4": return "mp4"
        case "video/mp2t": return "ts"
        case "video/x-matroska": return "mkv"
        case "video/webm": return "webm"
        case "video/quicktime": return "mov"
        case "video/x-msvideo": return "avi"
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        default: return "bin"
        }
    }
}
#endif
