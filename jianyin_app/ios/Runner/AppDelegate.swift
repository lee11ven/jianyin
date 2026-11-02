import AVFoundation
import Flutter
import UIKit
import MediaPipeTasksVision

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var visionPlugin: MediaPipeVisionPlugin?
  private var pcmPlayerPlugin: PcmPlayerPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let plugin = MediaPipeVisionPlugin()
      visionPlugin = plugin
      let channel = FlutterMethodChannel(
        name: MediaPipeVisionPlugin.channelName,
        binaryMessenger: controller.binaryMessenger
      )
channel.setMethodCallHandler { call, result in
        plugin.handle(call, result: result)
      }

      // 流式 PCM 播放桥：与视觉桥并列注册，二者互不影响。
      let audioPlugin = PcmPlayerPlugin()
      pcmPlayerPlugin = audioPlugin
      let audioChannel = FlutterMethodChannel(
        name: PcmPlayerPlugin.channelName,
        binaryMessenger: controller.binaryMessenger
      )
      audioChannel.setMethodCallHandler { call, result in
        audioPlugin.handle(call, result: result)
      }
    }
    return ok
  }
}

/// Dual-platform MethodChannel handler (iOS).
/// Contract: format=rgba contiguous RGBA8888; IMAGE mode Pose + Hands.
final class MediaPipeVisionPlugin: NSObject {
  static let channelName = "jianyin/mediapipe_vision"

  private var pose: PoseLandmarker?
  private var hands: HandLandmarker?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ensureReady":
      do {
        let args = call.arguments as? [String: Any]
        let poseAsset = args?["poseAsset"] as? String ?? "assets/ml/pose_landmarker_lite.task"
        let handsAsset = args?["handsAsset"] as? String ?? "assets/ml/hand_landmarker.task"
        try ensureReady(poseAsset: poseAsset, handsAsset: handsAsset)
        result(nil)
      } catch {
        result(FlutterError(code: "mediapipe", message: error.localizedDescription, details: nil))
      }
    case "detectPose":
      result(detectPose(call: call))
    case "detectHands":
      result(detectHands(call: call))
    case "dispose":
      pose = nil
      hands = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensureReady(poseAsset: String, handsAsset: String) throws {
    if pose != nil && hands != nil { return }
    let posePath = try resolveModelPath(poseAsset)
    let handsPath = try resolveModelPath(handsAsset)

    let poseOptions = PoseLandmarkerOptions()
    poseOptions.baseOptions.modelAssetPath = posePath
    poseOptions.runningMode = .image
    poseOptions.numPoses = 1
    pose = try PoseLandmarker(options: poseOptions)

    let handOptions = HandLandmarkerOptions()
    handOptions.baseOptions.modelAssetPath = handsPath
    handOptions.runningMode = .image
    handOptions.numHands = 2
    hands = try HandLandmarker(options: handOptions)
  }

  private func resolveModelPath(_ key: String) throws -> String {
    let fm = FileManager.default
    let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let fileName = (key as NSString).lastPathComponent
    let out = cache.appendingPathComponent(fileName)
    if fm.fileExists(atPath: out.path) {
      let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      if size > 0 { return out.path }
    }

    let candidates: [String] = [
      Bundle.main.bundlePath + "/flutter_assets/\(key)",
      Bundle.main.resourcePath.map { $0 + "/flutter_assets/\(key)" } ?? "",
    ]
    for path in candidates where !path.isEmpty && fm.fileExists(atPath: path) {
      try? fm.removeItem(at: out)
      try fm.copyItem(atPath: path, toPath: out.path)
      return out.path
    }
    throw NSError(
      domain: "MediaPipeVision",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Missing model asset \(key)"]
    )
  }

  private func detectPose(call: FlutterMethodCall) -> [String: Any]? {
    guard let landmarker = pose, let mpImage = makeMPImage(call: call) else { return nil }
    guard let detection = try? landmarker.detect(image: mpImage),
          let first = detection.landmarks.first else { return nil }
    let points: [[String: Double]] = first.map { p in
      let v = landmarkVisibility(p)
      return ["x": Double(p.x), "y": Double(p.y), "z": Double(p.z), "v": v]
    }
    return ["landmarks": points]
  }

  private func detectHands(call: FlutterMethodCall) -> [String: Any]? {
    guard let landmarker = hands, let mpImage = makeMPImage(call: call) else { return nil }
    guard let detection = try? landmarker.detect(image: mpImage),
          !detection.landmarks.isEmpty else { return nil }
    var handsOut: [[String: Any]] = []
    for i in 0..<detection.landmarks.count {
      let lm = detection.landmarks[i]
      let points: [[String: Double]] = lm.map { p in
        let v = landmarkVisibility(p)
        return ["x": Double(p.x), "y": Double(p.y), "z": Double(p.z), "v": v]
      }
      var label = "Right"
      var score = 0.0
      if i < detection.handedness.count, let cat = detection.handedness[i].first {
        label = cat.categoryName
        score = Double(cat.score)
      }
      handsOut.append([
        "landmarks": points,
        "handedness": label,
        "score": score,
      ])
    }
    return ["hands": handsOut]
  }

  private func landmarkVisibility(_ p: NormalizedLandmark) -> Double {
    // MediaPipeTasksVision exposes optional NSNumber visibility/presence.
    let one = NSNumber(value: 1.0)
    let vis = Double(truncating: p.visibility ?? one)
    let pres = Double(truncating: p.presence ?? one)
    return min(vis.isNaN ? 1 : vis, pres.isNaN ? 1 : pres)
  }

  private func makeMPImage(call: FlutterMethodCall) -> MPImage? {
    guard let args = call.arguments as? [String: Any],
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          let flutterData = args["bytes"] as? FlutterStandardTypedData else { return nil }
    let data = flutterData.data
    guard data.count >= width * height * 4 else { return nil }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )
    guard let provider = CGDataProvider(data: data as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else { return nil }
return try? MPImage(uiImage: UIImage(cgImage: cgImage))
  }
}

/// 流式 PCM 播放桥（iOS）。
///
/// 契约：只接受 **PCM s16le / 16 kHz / mono**（见 docs/api/protocol.md）。
/// 实现：`AVAudioEngine` + `AVAudioPlayerNode`，Int16 buffer 逐片入队；
/// 音频会话用 `playback` + `spokenAudio`，为「熄屏/后台续播」提供系统能力
/// （见 docs/design/客户端APP/architecture.md 平台落点）。
/// `bufferedFrames` 以「已排队帧数 − 播放器已推进帧数」近似原生水位，
/// 供 Dart 侧抖动缓冲判定欠载。
final class PcmPlayerPlugin: NSObject {
  static let channelName = "jianyin/pcm_player"

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var format: AVAudioFormat?
  private var started = false
  private var scheduledFrames = 0

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      open(call, result: result)
    case "write":
      write(call, result: result)
    case "bufferedFrames":
      result(bufferedFrames())
    case "flush":
      flush()
      result(nil)
    case "close":
      close()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func open(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let sampleRate = (args["sampleRate"] as? NSNumber)?.doubleValue ?? 16000
    let channels = (args["channels"] as? NSNumber)?.uint32Value ?? 1

    close()

    guard let pcmFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: sampleRate,
      channels: AVAudioChannelCount(channels),
      interleaved: true
    ) else {
      result(false)
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      try session.setActive(true)

      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: pcmFormat)
      try engine.start()
      player.play()
      format = pcmFormat
      started = true
      scheduledFrames = 0
      result(true)
    } catch {
      result(false)
    }
  }

  private func write(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let data = call.arguments as? FlutterStandardTypedData,
          let pcmFormat = format,
          started
    else {
      result(nil)
      return
    }

    let bytes = data.data
    let frames = bytes.count / MemoryLayout<Int16>.size
    guard frames > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(frames))
    else {
      result(nil)
      return
    }

    buffer.frameLength = AVAudioFrameCount(frames)
    bytes.withUnsafeBytes { raw in
      if let destination = buffer.int16ChannelData?.pointee,
         let source = raw.bindMemory(to: Int16.self).baseAddress {
        destination.update(from: source, count: frames)
      }
    }

    player.scheduleBuffer(buffer, completionHandler: nil)
    scheduledFrames += frames
    if !player.isPlaying { player.play() }
    result(nil)
  }

  /// 近似水位：已排队帧数 − 播放器已推进帧数（不足时为 0）。
  private func bufferedFrames() -> Int {
    guard started,
          let nodeTime = player.lastRenderTime,
          let playerTime = player.playerTime(forNodeTime: nodeTime)
    else { return 0 }
    let remaining = scheduledFrames - Int(playerTime.sampleTime)
    return remaining > 0 ? remaining : 0
  }

  private func flush() {
    player.stop()
    scheduledFrames = 0
    if started { player.play() }
  }

  private func close() {
    player.stop()
    if engine.isRunning { engine.stop() }
    if started {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    started = false
    format = nil
    scheduledFrames = 0
  }
}
