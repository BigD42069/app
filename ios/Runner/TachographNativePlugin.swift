import Flutter
import Foundation
import Mobile

private let channelName = "tachograph_native"

private enum ParserInitError: Error {
  case missingCertificates(String)
  case createFailed(String)
}

public class TachographNativePlugin: NSObject, FlutterPlugin {
  private var cachedParser: MobileParser?
  private var cachedPks1: String?
  private var cachedPks2: String?
  private var registrar: FlutterPluginRegistrar?
  private let parserQueue = DispatchQueue(label: "tachograph_native.parse")

  private func assetPathVariants(_ asset: String) -> [String] {
    guard let encoded = asset.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
      return [asset]
    }
    if encoded == asset {
      return [asset]
    }
    return [asset, encoded]
  }

  private func requiredFileCandidates(_ requiredFile: String) -> [String] {
    var items: [String] = [requiredFile]
    let underscored = requiredFile.replacingOccurrences(of: " ", with: "_")
    if underscored != requiredFile {
      items.append(underscored)
    }
    if let encoded = requiredFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
       encoded != requiredFile {
      items.append(encoded)
    }
    var seen = Set<String>()
    return items.filter { seen.insert($0).inserted }
  }

  private func ensureRequiredFile(in targetDir: URL, requiredFile: String) -> Bool {
    let fm = FileManager.default
    let requiredURL = targetDir.appendingPathComponent(requiredFile)
    if fm.fileExists(atPath: requiredURL.path) {
      return true
    }
    for candidate in requiredFileCandidates(requiredFile) where candidate != requiredFile {
      let candidateURL = targetDir.appendingPathComponent(candidate)
      if fm.fileExists(atPath: candidateURL.path) {
        do {
          try fm.copyItem(at: candidateURL, to: requiredURL)
        } catch {
          // ignore copy errors; we only need the target if it exists
        }
        if fm.fileExists(atPath: requiredURL.path) {
          return true
        }
      }
    }
    return false
  }

  private func resolveBundleDir(_ name: String, requiredFile: String) -> String? {
    let fm = FileManager.default
    var candidates: [URL] = []
    let requiredComponent = requiredFile

    if let url = Bundle.main.url(forResource: name, withExtension: nil) {
      candidates.append(url.appendingPathComponent(requiredComponent))
    }
    if let resourceURL = Bundle.main.resourceURL {
      candidates.append(resourceURL.appendingPathComponent(name).appendingPathComponent(requiredComponent))
      candidates.append(
        resourceURL
          .appendingPathComponent("flutter_assets/assets/pkg/certificates/\(name)")
          .appendingPathComponent(requiredComponent)
      )
      candidates.append(
        resourceURL
          .appendingPathComponent("Frameworks/App.framework/flutter_assets/assets/pkg/certificates/\(name)")
          .appendingPathComponent(requiredComponent)
      )
    }

    let pluginBundle = Bundle(for: TachographNativePlugin.self)
    if let url = pluginBundle.url(forResource: name, withExtension: nil) {
      candidates.append(url.appendingPathComponent(requiredComponent))
    }

    if let registrar {
      let assetPath = "assets/pkg/certificates/\(name)/\(requiredFile)"
      let key = registrar.lookupKey(forAsset: assetPath)
      if let path = bundleAssetPath(key) ?? bundleAssetPath(assetPath) {
        let dir = (path as NSString).deletingLastPathComponent
        let requiredPath = (dir as NSString).appendingPathComponent(requiredFile)
        if fm.fileExists(atPath: requiredPath) {
          return dir
        }
      }
    }

    for url in candidates {
      if fm.fileExists(atPath: url.path) {
        return (url.deletingLastPathComponent()).path
      }
    }
    return nil
  }

  private func bundleAssetPath(_ asset: String) -> String? {
    for candidate in assetPathVariants(asset) {
      if let path = Bundle.main.path(forResource: candidate, ofType: nil, inDirectory: "Frameworks/App.framework/flutter_assets") {
        return path
      }
      if let path = Bundle.main.path(forResource: candidate, ofType: nil, inDirectory: "flutter_assets") {
        return path
      }
    }
    return nil
  }

  private func flutterAssetFilePath(_ asset: String) -> String? {
    let fm = FileManager.default
    if let registrar {
      let key = registrar.lookupKey(forAsset: asset)
      for candidate in assetPathVariants(key) {
        if let path = bundleAssetPath(candidate) {
          return path
        }
      }
    }

    if let resourceURL = Bundle.main.resourceURL {
      for candidate in assetPathVariants(asset) {
        let flutterAssets = resourceURL
          .appendingPathComponent("flutter_assets")
          .appendingPathComponent(candidate)
        if fm.fileExists(atPath: flutterAssets.path) {
          return flutterAssets.path
        }
        let appFramework = resourceURL
          .appendingPathComponent("Frameworks/App.framework/flutter_assets")
          .appendingPathComponent(candidate)
        if fm.fileExists(atPath: appFramework.path) {
          return appFramework.path
        }
      }
    }
    return nil
  }

  private func assetManifestPath() -> String? {
    if let path = flutterAssetFilePath("AssetManifest.json") {
      return path
    }
    if let resourceURL = Bundle.main.resourceURL {
      let candidate = resourceURL.appendingPathComponent("flutter_assets/AssetManifest.json").path
      if FileManager.default.fileExists(atPath: candidate) {
        return candidate
      }
      let appFramework = resourceURL
        .appendingPathComponent("Frameworks/App.framework/flutter_assets/AssetManifest.json").path
      if FileManager.default.fileExists(atPath: appFramework) {
        return appFramework
      }
    }
    return nil
  }

  private func ensurePksDir(name: String, requiredFile: String) -> String? {
    let fm = FileManager.default
    guard let baseURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    let targetDir = baseURL.appendingPathComponent(name, isDirectory: true)
    if ensureRequiredFile(in: targetDir, requiredFile: requiredFile) {
      return targetDir.path
    }

    guard let manifestPath = assetManifestPath() else {
      return nil
    }
    guard
      let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    let prefix = "assets/pkg/certificates/\(name)/"
    let assets = json.keys.filter { $0.hasPrefix(prefix) }
    if assets.isEmpty {
      return nil
    }

    do {
      try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
    } catch {
      return nil
    }

    for asset in assets {
      guard let sourcePath = flutterAssetFilePath(asset) else { continue }
      let rel = String(asset.dropFirst(prefix.count))
      let destURL = targetDir.appendingPathComponent(rel)
      if fm.fileExists(atPath: destURL.path) {
        continue
      }
      do {
        try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: sourcePath), to: destURL)
      } catch {
        continue
      }
    }

    if ensureRequiredFile(in: targetDir, requiredFile: requiredFile) {
      return targetDir.path
    }
    return nil
  }

  private func makeParser(pks1Override: String?, pks2Override: String?) throws -> MobileParser {
    let pks1 = (pks1Override?.isEmpty == false)
      ? pks1Override
      : (ensurePksDir(name: "pks1", requiredFile: "EC_PK.bin") ??
        resolveBundleDir("pks1", requiredFile: "EC_PK.bin"))
    let pks2 = (pks2Override?.isEmpty == false)
      ? pks2Override
      : (ensurePksDir(name: "pks2", requiredFile: "ERCA Gen2 (1) Root Certificate.bin") ??
        resolveBundleDir("pks2", requiredFile: "ERCA Gen2 (1) Root Certificate.bin"))

    guard let pks1 else { throw ParserInitError.missingCertificates("pks1") }
    guard let pks2 else { throw ParserInitError.missingCertificates("pks2") }

    if let existing = cachedParser, cachedPks1 == pks1, cachedPks2 == pks2 {
      return existing
    }

    var err: NSError?
    let created = MobileCreateParser(pks1, pks2, &err)
    if let err = err {
      throw err
    }
    guard let parser = created else {
      throw ParserInitError.createFailed("MobileCreateParser returned nil")
    }

    cachedParser = parser
    cachedPks1 = pks1
    cachedPks2 = pks2
    NSLog("tachograph_native: parser instantiated")
    return parser
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = TachographNativePlugin()
    instance.registrar = registrar
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "parseDdd":
      handleParse(call: call, result: result)
    case "cancelActiveParse":
      DispatchQueue.main.async {
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleParse(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let payloadData = args["payload"] as? FlutterStandardTypedData
    else {
      result(FlutterError(code: "invalid-arguments", message: "Missing payload", details: nil))
      return
    }

    let source = (args["source"] as? String) ?? "card"
    let mode = source.lowercased() == "vu" ? "vu" : "card"
    let timeoutMs = (args["timeoutMs"] as? NSNumber)?.intValue ?? 0
    let pks1Dir = (args["pks1Dir"] as? String)
    let pks2Dir = (args["pks2Dir"] as? String)
    let payload = payloadData.data
    if payload.isEmpty {
      result(FlutterError(code: "invalid-arguments", message: "input payload must not be empty", details: nil))
      return
    }

    parserQueue.async { [weak self] in
      guard let self else { return }
      do {
        let parser = try self.makeParser(pks1Override: pks1Dir, pks2Override: pks2Dir)
        let parsed: MobileParseResult
        if timeoutMs > 0 {
          parsed = try parser.parse(withTimeout: payload, mode: mode, timeoutMillis: timeoutMs)
        } else if mode == "vu" {
          parsed = try parser.parseVehicleUnit(payload)
        } else {
          parsed = try parser.parseCard(payload)
        }

        let payloadJson = parsed.payloadJSON
        let map: [String: Any?] = [
          "status": "ok",
          "json": payloadJson.isEmpty ? nil : payloadJson,
          "verified": parsed.verified,
          "verificationLog": nil,
          "errorDetails": nil,
        ]
        DispatchQueue.main.async {
          NSLog("tachograph_native: parse success mode=\(mode)")
          result(map)
        }
      } catch let initError as ParserInitError {
        let message: String
        switch initError {
        case .missingCertificates(let name):
          message = "PKS dir not found: \(name)"
        case .createFailed(let detail):
          message = detail
        }
        DispatchQueue.main.async {
          result(FlutterError(code: "parser-init", message: message, details: nil))
        }
      } catch {
        let nsError = error as NSError
        DispatchQueue.main.async {
          NSLog("tachograph_native: parse error mode=\(mode) err=\(nsError.localizedDescription)")
          result(FlutterError(code: "parser-error", message: nsError.localizedDescription, details: nil))
        }
      }
    }
  }
}
