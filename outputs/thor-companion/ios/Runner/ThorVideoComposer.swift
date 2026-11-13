import Foundation
import AVFoundation

/// Composes the two independent, bounded recording tracks without changing their aspect ratios.
enum ThorVideoComposer {
  static func compose(_ sources: [URL], offsets: [Double], fps: Int = 30, directory: URL,
                      completion: @escaping (Result<URL, Error>) -> Void) {
    func failure(_ text: String) -> NSError { NSError(domain: "ThorRecording", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    guard sources.count == 1 || sources.count == 2, offsets.count == sources.count, [30,60].contains(fps), offsets.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 10000 }) else {
      completion(.failure(failure("Invalid recording tracks."))); return
    }
    let assets = sources.map { AVURLAsset(url: $0) }
    var tracks: [AVAssetTrack] = []
    for asset in assets {
      guard let track = asset.tracks(withMediaType: .video).first,
            asset.duration.seconds.isFinite, asset.duration.seconds > 0, asset.duration.seconds <= 190 else {
        completion(.failure(failure("A recording could not be opened."))); return
      }
      tracks.append(track)
    }
    let composition = AVMutableComposition()
    let commonStart = offsets.max() ?? 0
    let starts = offsets.map { CMTime(value: Int64((commonStart - $0).rounded()), timescale: 1000) }
    var duration = CMTimeSubtract(assets[0].duration, starts[0])
    for index in assets.indices { duration = CMTimeMinimum(duration, CMTimeSubtract(assets[index].duration, starts[index])) }
    duration = CMTimeConvertScale(duration, timescale: Int32(fps), method: .roundTowardZero)
    guard duration.isNumeric, duration.seconds > 0 else { completion(.failure(failure("The recording is too short to combine."))); return }
    var destination: [AVCompositionTrack] = []
    var bounds: [CGRect] = []
    do {
      for index in tracks.indices {
        let source = tracks[index]
        let rect = CGRect(origin: .zero, size: source.naturalSize).applying(source.preferredTransform)
        guard rect.width.isFinite, rect.height.isFinite, abs(rect.width) > 0, abs(rect.height) > 0,
              abs(rect.width) <= 4096, abs(rect.height) <= 4096,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
          throw failure("Unsupported recording dimensions.")
        }
        try track.insertTimeRange(CMTimeRange(start: starts[index], duration: duration), of: source, at: .zero)
        destination.append(track); bounds.append(rect)
      }
    } catch { completion(.failure(error)); return }
    if let sound = assets[0].tracks(withMediaType: .audio).first,
       let destinationAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      let available = CMTimeSubtract(CMTimeRangeGetEnd(sound.timeRange), starts[0])
      if available.seconds > 0 {
        do { try destinationAudio.insertTimeRange(CMTimeRange(start: starts[0], duration: CMTimeMinimum(duration, available)), of: sound, at: .zero) }
        catch { completion(.failure(error)); return }
      }
    }
    let width = ceil((bounds.map { abs($0.width) }.max() ?? 0) / 2) * 2
    let height = ceil(bounds.reduce(0) { $0 + abs($1.height) } / 2) * 2
    let video = AVMutableVideoComposition()
    video.renderSize = CGSize(width: width, height: height)
    video.frameDuration = CMTime(value: 1, timescale: Int32(fps))
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    var layers: [AVVideoCompositionLayerInstruction] = []
    for index in tracks.indices {
      let rect = bounds[index]
      let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: destination[index])
      let transform = tracks[index].preferredTransform
        .concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        .concatenating(CGAffineTransform(translationX: (width - abs(rect.width)) / 2, y: bounds.prefix(index).reduce(0) { $0 + abs($1.height) }))
      layer.setTransform(transform, at: .zero); layers.append(layer)
    }
    instruction.layerInstructions = layers
    video.instructions = [instruction]
    let output = directory.appendingPathComponent("Thor-both-\(UUID().uuidString).mp4")
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      completion(.failure(failure("Video export is unavailable."))); return
    }
    export.videoComposition = video; export.outputURL = output; export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    export.exportAsynchronously {
      if export.status == .completed { completion(.success(output)) }
      else { try? FileManager.default.removeItem(at: output); completion(.failure(export.error ?? failure("Could not combine recordings."))) }
    }
  }
}
