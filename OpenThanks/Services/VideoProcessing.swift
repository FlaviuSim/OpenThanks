import AVFoundation
import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Shared helpers for picking, compressing, and previewing appreciation videos.
enum VideoProcessing {
    static let maxUploadBytes = 50 * 1024 * 1024

    /// PhotosPicker transferable for library movies.
    struct MovieFile: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: UTType.movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ot-pick-\(UUID().uuidString).\(ext)")
                if FileManager.default.fileExists(atPath: copy.path) {
                    try FileManager.default.removeItem(at: copy)
                }
                try FileManager.default.copyItem(at: received.file, to: copy)
                return Self(url: copy)
            }
        }
    }

    static func isVideoContentTypes(_ types: [UTType]) -> Bool {
        types.contains { type in
            type.conforms(to: UTType.audiovisualContent) && !type.conforms(to: UTType.image)
        }
    }

    /// Export a library video to H.264 MP4 under the web size limit, plus a poster frame.
    static func prepareForUpload(from sourceURL: URL) async throws -> PreparedVideo {
        let exportedURL = try await exportMP4(from: sourceURL)
        let data = try Data(contentsOf: exportedURL)
        guard data.count <= maxUploadBytes else {
            try? FileManager.default.removeItem(at: exportedURL)
            throw VideoError.tooLarge
        }
        let poster: UIImage?
        if let frame = await thumbnail(from: exportedURL) {
            poster = frame
        } else {
            poster = await thumbnail(from: sourceURL)
        }
        return PreparedVideo(
            uploadData: data,
            contentType: "video/mp4",
            previewFileURL: exportedURL,
            poster: poster
        )
    }

    static func thumbnail(from url: URL, at seconds: Double = 0.1) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        do {
            let (cg, _) = try await generator.image(at: time)
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    private static func exportMP4(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ot-upload-\(UUID().uuidString).mp4")

        // Already a small-enough MP4 — skip re-encode when possible.
        if sourceURL.pathExtension.lowercased() == "mp4",
           let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let size = attrs[.size] as? Int,
           size > 0, size <= maxUploadBytes {
            try FileManager.default.copyItem(at: sourceURL, to: out)
            return out
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else {
            throw VideoError.exportFailed
        }

        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw VideoError.exportFailed
        }
        return out
    }

    struct PreparedVideo {
        let uploadData: Data
        let contentType: String
        let previewFileURL: URL
        let poster: UIImage?
    }

    enum VideoError: LocalizedError {
        case tooLarge
        case exportFailed
        case loadFailed

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "That video is too large. Please pick one under 50MB."
            case .exportFailed:
                return "Couldn't prepare that video. Try another one."
            case .loadFailed:
                return "Couldn't load that video. Try another one."
            }
        }
    }
}
