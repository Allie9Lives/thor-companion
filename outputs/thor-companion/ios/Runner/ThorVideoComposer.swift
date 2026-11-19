import Foundation
import AVFoundation
import VideoToolbox
import Flutter

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

// ThorLiveVideo is kept in this file so the Xcode project needs no new source entry.

/// Decodes one Thor screen's raw H.264 live view (id 0 top, 1 bottom) into a Flutter texture.
/// Dart owns the pinned network stream; size and reset callbacks carry the id.
final class ThorLiveVideo: NSObject, FlutterTexture {
  private let textures: FlutterTextureRegistry
  private let channel: FlutterMethodChannel
  private let id: Int
  private let queue = DispatchQueue(label: "ThorLiveVideo")
  private let lock = NSLock()
  private var latest: CVPixelBuffer?
  private var textureId: Int64 = 0
  private var session: VTDecompressionSession?
  private var format: CMVideoFormatDescription?
  private var sps: Data?, pps: Data?
  private var carry = Data()
  private var waitingForKeyframe = true

  init(textures: FlutterTextureRegistry, channel: FlutterMethodChannel, id: Int) {
    self.textures = textures; self.channel = channel; self.id = id
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock(); defer { lock.unlock() }
    guard let buffer = latest else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  func handle(_ method: String, data: Data?, result: @escaping FlutterResult) {
    switch method {
    case "start":
      queue.async { self.reset() }
      if textureId != 0 { textures.unregisterTexture(textureId) }
      textureId = textures.register(self)
      result(textureId)
    case "feed":
      guard let data, data.count <= 4 << 20 else {
        result(FlutterError(code: "live", message: "Invalid video data", details: nil)); return
      }
      queue.async { self.feed(data) }
      result(nil)
    case "stop":
      queue.async { self.reset() }
      if textureId != 0 { textures.unregisterTexture(textureId); textureId = 0 }
      lock.lock(); latest = nil; lock.unlock()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reset() {
    if let session { VTDecompressionSessionInvalidate(session) }
    session = nil; format = nil; sps = nil; pps = nil; carry = Data(); waitingForKeyframe = true
  }

  private func needsRestart() {
    reset()
    DispatchQueue.main.async { self.channel.invokeMethod("reset", arguments: ["id": self.id]) }
  }

  // screenrecord emits 4-byte start codes; parameter sets repeat unchanged when it restarts every 180 s.
  private func feed(_ bytes: Data) {
    carry.append(bytes)
    let data = [UInt8](carry)
    var starts: [Int] = []
    var i = 0
    while i + 3 < data.count {
      if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 1 { starts.append(i); i += 4 } else { i += 1 }
    }
    guard let last = starts.last else { if carry.count > 8 << 20 { carry = Data() }; return }
    for n in 0..<(starts.count - 1) { nal(Array(data[starts[n] + 4 ..< starts[n + 1]])) }
    carry = Data(data[last...])
  }

  private func nal(_ unit: [UInt8]) {
    guard let first = unit.first else { return }
    switch first & 31 {
    case 7: if session == nil { sps = Data(unit) }
    case 8: if session == nil { pps = Data(unit); configure() }
    case 5: waitingForKeyframe = false; decode(unit)
    case 1: if !waitingForKeyframe { decode(unit) }
    default: break
    }
  }

  private func configure() {
    guard session == nil, let sps, let pps else { return }
    var description: CMFormatDescription?
    let status = sps.withUnsafeBytes { s in
      pps.withUnsafeBytes { p in
        let pointers = [s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
        let sizes = [sps.count, pps.count]
        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
          allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers,
          parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
      }
    }
    guard status == noErr, let description else { return }
    let attributes: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    var callback = VTDecompressionOutputCallbackRecord(
      decompressionOutputCallback: { refcon, _, status, _, image, _, _ in
        guard status == noErr, let image, let refcon else { return }
        Unmanaged<ThorLiveVideo>.fromOpaque(refcon).takeUnretainedValue().show(image)
      },
      decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
    var created: VTDecompressionSession?
    guard VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: description,
                                       decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
                                       outputCallback: &callback, decompressionSessionOut: &created) == noErr,
          let created else { return }
    VTSessionSetProperty(created, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    session = created; format = description
    let size = CMVideoFormatDescriptionGetDimensions(description)
    DispatchQueue.main.async {
      self.channel.invokeMethod("size", arguments: ["id": self.id, "width": Int(size.width), "height": Int(size.height)])
    }
  }

  private func decode(_ unit: [UInt8]) {
    guard let session, let format else { return }
    let length = unit.count + 4
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                             blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                             dataLength: length, flags: 0, blockBufferOut: &block) == noErr,
          let block else { return }
    var prefixed = withUnsafeBytes(of: UInt32(unit.count).bigEndian) { [UInt8]($0) }
    prefixed.append(contentsOf: unit)
    guard CMBlockBufferReplaceDataBytes(with: prefixed, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr else { return }
    var sample: CMSampleBuffer?
    var sampleSize = length
    guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                    sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                    sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr,
          let sample else { return }
    let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], frameRefcon: nil, infoFlagsOut: nil)
    // iOS invalidates the session while backgrounded; a fresh stream brings a new keyframe.
    if status == kVTInvalidSessionErr { needsRestart() }
  }

  private func show(_ image: CVImageBuffer) {
    lock.lock(); latest = image; lock.unlock()
    DispatchQueue.main.async { if self.textureId != 0 { self.textures.textureFrameAvailable(self.textureId) } }
  }
}
