import Flutter
import Foundation

#if canImport(Mobile)
import Mobile
#endif

private let channelName = "tachograph_native"

public class TachographNativePlugin: NSObject, FlutterPlugin {
  #if canImport(Mobile)
  private var parser: MobileParser?
  #endif

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = TachographNativePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "parseDdd":
      handleParse(call: call, result: result)
    case "cancelActiveParse":
      handleCancel(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleParse(call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(Mobile)
    guard
      let args = call.arguments as? [String: Any],
      let payloadData = args["payload"] as? FlutterStandardTypedData,
      let source = args["source"] as? String
    else {
      result(FlutterError(code: "invalid-arguments", message: "Missing payload or source", details: nil))
      return
    }

    let pks1Dir = args["pks1Dir"] as? String ?? ""
    let pks2Dir = args["pks2Dir"] as? String ?? ""
    let strictMode = args["strictMode"] as? Bool ?? false
    let timeout = args["timeoutMs"] as? NSNumber

    do {
      let parser = try ensureParser()
      let options = MobileParseOptions()
      options.source = source
      options.pks1Dir = pks1Dir
      options.pks2Dir = pks2Dir
      options.strictMode = strictMode
      if let timeout = timeout {
        options.timeoutMs = timeout.int64Value
      }

      let parseResult = try parser.parseDdd(payloadData.data, opts: options)
      let response: [String: Any?] = [
        "status": parseResult.status,
        "json": parseResult.json.isEmpty ? nil : parseResult.json,
        "verified": parseResult.verified,
        "verificationLog": parseResult.verificationLog.isEmpty ? nil : parseResult.verificationLog,
        "errorDetails": parseResult.errorDetails.isEmpty ? nil : parseResult.errorDetails,
      ]
      result(response)
    } catch let error as MobileNativeError {
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      result(FlutterError(code: "parser-error", message: error.localizedDescription, details: nil))
    }
    #else
    result(FlutterError(code: "missing-native-lib", message: "Mobile framework not linked", details: nil))
    #endif
  }

  private func handleCancel(result: @escaping FlutterResult) {
    #if canImport(Mobile)
    parser?.cancelActiveParse()
    #endif
    result(nil)
  }

  #if canImport(Mobile)
  private func ensureParser() throws -> MobileParser {
    if let parser = parser {
      return parser
    }
    let parser = MobileParser()
    self.parser = parser
    return parser
  }
  #endif
}
