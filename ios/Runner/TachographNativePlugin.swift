import Flutter
import Foundation
import ObjectiveC.runtime

private let channelName = "tachograph_native"

public class TachographNativePlugin: NSObject, FlutterPlugin {
  private var binding: GomobileBinding?

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
    let timeout = (args["timeoutMs"] as? NSNumber)?.int64Value

    do {
      let binding = try ensureBinding()
      let parseResult = try binding.parse(
        payload: payloadData.data,
        source: source,
        pks1Dir: pks1Dir,
        pks2Dir: pks2Dir,
        strictMode: strictMode,
        timeoutMs: timeout
      )
      result(parseResult)
    } catch NativeBridgeError.missingBindings {
      result(FlutterError(code: "missing-native-lib", message: "Mobile framework not linked", details: nil))
    } catch let failure as GomobileBinding.ParseFailure {
      switch failure {
      case let .native(code, message):
        result(FlutterError(code: code, message: message, details: nil))
      case let .unexpected(message):
        result(FlutterError(code: "parser-error", message: message, details: nil))
      }
    } catch {
      result(FlutterError(code: "parser-error", message: error.localizedDescription, details: nil))
    }
  }

  private func handleCancel(result: @escaping FlutterResult) {
    binding?.cancel()
    result(nil)
  }

  private func ensureBinding() throws -> GomobileBinding {
    if let binding = binding {
      return binding
    }
    guard let binding = GomobileBinding() else {
      throw NativeBridgeError.missingBindings
    }
    self.binding = binding
    return binding
  }
}

private enum NativeBridgeError: Error {
  case missingBindings
}

private final class GomobileBinding {
  enum ParseFailure: Error {
    case native(code: String, message: String?)
    case unexpected(String)
  }

  private typealias ParseFunction = @convention(c) (
    AnyObject,
    Selector,
    NSData,
    AnyObject?,
    UnsafeMutablePointer<NSError?>?
  ) -> Unmanaged<AnyObject>?

  private let parser: NSObject
  private let parseSelector: Selector
  private let parseFunction: ParseFunction
  private let cancelSelector: Selector?
  private let closeSelector: Selector?
  private let parseOptionsType: NSObject.Type
  private let nativeErrorClass: AnyClass?

  init?() {
    guard let parserType = GomobileBinding.classType(named: [
      "MobileParser",
      "Mobile.MobileParser",
      "Parser",
      "Mobile.Parser",
    ]) else {
      return nil
    }

    let parser = parserType.init()

    guard let (selector, function) = GomobileBinding.loadParseFunction(from: parser) else {
      return nil
    }

    guard let optionsType = GomobileBinding.classType(named: [
      "MobileParseOptions",
      "Mobile.MobileParseOptions",
      "MobileParseoptions",
      "Mobile.MobileParseoptions",
      "ParseOptions",
      "Mobile.ParseOptions",
    ]) else {
      return nil
    }

    self.parser = parser
    parseSelector = selector
    parseFunction = function
    cancelSelector = GomobileBinding.selector(on: parser, names: [
      "cancelActiveParse",
      "CancelActiveParse",
    ])
    closeSelector = GomobileBinding.selector(on: parser, names: [
      "close",
      "Close",
    ])
    parseOptionsType = optionsType
    nativeErrorClass = GomobileBinding.anyClass(named: [
      "MobileNativeError",
      "Mobile.MobileNativeError",
      "NativeError",
      "Mobile.NativeError",
    ])
  }

  deinit {
    if let closeSelector = closeSelector, parser.responds(to: closeSelector) {
      parser.perform(closeSelector)
    }
  }

  func parse(
    payload: Data,
    source: String,
    pks1Dir: String,
    pks2Dir: String,
    strictMode: Bool,
    timeoutMs: Int64?
  ) throws -> [String: Any?] {
    let options = parseOptionsType.init()

    applySetters(on: options, names: ["setSource:", "setMode:"], value: source)
    applySetters(on: options, names: ["setPks1Dir:", "setPKS1Dir:"], value: pks1Dir)
    applySetters(on: options, names: ["setPks2Dir:", "setPKS2Dir:"], value: pks2Dir)
    applySetters(on: options, names: ["setStrictMode:", "setIsStrictMode:"], value: strictMode)

    if let timeoutMs = timeoutMs, timeoutMs > 0 {
      applySetters(
        on: options,
        names: ["setTimeoutMs:", "setTimeout:", "setTimeoutMS:"],
        value: timeoutMs
      )
    }

    var parseError: NSError?
    let resultObject = withUnsafeMutablePointer(to: &parseError) { errorPointer -> NSObject? in
      let unmanagedResult = parseFunction(
        parser,
        parseSelector,
        payload as NSData,
        options,
        errorPointer
      )
      if let value = unmanagedResult?.takeUnretainedValue() {
        return value as? NSObject
      }
      return nil
    }

    if let error = parseError {
      let errorObject = error as NSObject
      if let nativeErrorClass = nativeErrorClass, errorObject.isKind(of: nativeErrorClass) {
        let code = GomobileBinding.stringValue(from: errorObject, selectors: ["code", "getCode"]) ?? "parser-error"
        let message = GomobileBinding.stringValue(from: errorObject, selectors: ["message", "getMessage"])
        throw ParseFailure.native(code: code, message: message)
      }
      if let code = GomobileBinding.stringValue(from: errorObject, selectors: ["code", "getCode"]) {
        let message = GomobileBinding.stringValue(from: errorObject, selectors: ["message", "getMessage"]) ?? error.localizedDescription
        throw ParseFailure.native(code: code, message: message)
      }
      throw ParseFailure.unexpected(error.localizedDescription)
    }

    guard let parseResult = resultObject else {
      throw ParseFailure.unexpected("native parser returned no result")
    }

    let status = GomobileBinding.stringValue(from: parseResult, selectors: ["status", "getStatus"]) ?? "unknown"
    let json = GomobileBinding.stringValue(from: parseResult, selectors: ["json", "getJson"])
    let verified = GomobileBinding.boolValue(from: parseResult, selectors: ["verified", "isVerified", "getVerified"]) ?? false
    let verificationLog = GomobileBinding.stringValue(
      from: parseResult,
      selectors: ["verificationLog", "getVerificationLog"]
    )
    let errorDetails = GomobileBinding.stringValue(
      from: parseResult,
      selectors: ["errorDetails", "getErrorDetails"]
    )

    return [
      "status": status,
      "json": json?.isEmpty == true ? nil : json,
      "verified": verified,
      "verificationLog": verificationLog?.isEmpty == true ? nil : verificationLog,
      "errorDetails": errorDetails?.isEmpty == true ? nil : errorDetails,
    ]
  }

  func cancel() {
    guard let cancelSelector = cancelSelector, parser.responds(to: cancelSelector) else {
      return
    }
    parser.perform(cancelSelector)
  }

  private static func loadParseFunction(from parser: NSObject) -> (Selector, ParseFunction)? {
    let selectorNames = [
      "parseDdd:opts:error:",
      "parseDDD:opts:error:",
    ]

    for name in selectorNames {
      let selector = NSSelectorFromString(name)
      guard parser.responds(to: selector) else {
        continue
      }
      guard let implementation = class_getMethodImplementation(type(of: parser), selector) else {
        continue
      }
      let function = unsafeBitCast(implementation, to: ParseFunction.self)
      return (selector, function)
    }

    return nil
  }

  private static func selector(on object: NSObject, names: [String]) -> Selector? {
    for name in names {
      let selector = NSSelectorFromString(name)
      if object.responds(to: selector) {
        return selector
      }
    }
    return nil
  }

  private static func classType(named names: [String]) -> NSObject.Type? {
    for name in names {
      if let type = NSClassFromString(name) as? NSObject.Type {
        return type
      }
    }
    return nil
  }

  private static func anyClass(named names: [String]) -> AnyClass? {
    for name in names {
      if let type = NSClassFromString(name) {
        return type
      }
    }
    return nil
  }

  private func applySetters(on object: NSObject, names: [String], value: Any?) {
    GomobileBinding.applySetters(on: object, names: names, value: value)
  }

  private static func applySetters(on object: NSObject, names: [String], value: Any?) {
    for name in names {
      let selector = NSSelectorFromString(name)
      if object.responds(to: selector) {
        invoke(selector: selector, on: object, with: value)
        return
      }
    }
  }

  private static func invoke(selector: Selector, on object: NSObject, with value: Any?) {
    guard let method = class_getInstanceMethod(type(of: object), selector) else {
      object.perform(selector, with: value)
      return
    }

    let argumentCount = method_getNumberOfArguments(method)
    guard argumentCount >= 3 else {
      object.perform(selector, with: value)
      return
    }

    let argumentCString: UnsafeMutablePointer<Int8>? = method_copyArgumentType(method, 2)
    guard let argumentCString else {
      object.perform(selector, with: value)
      return
    }
    defer { free(argumentCString) }

    let argumentType = String(cString: argumentCString)

    switch argumentType {
    case "B", "c":
      typealias BoolSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
      guard let implementation = class_getMethodImplementation(type(of: object), selector) else {
        object.perform(selector, with: value)
        return
      }
      let function = unsafeBitCast(implementation, to: BoolSetter.self)
      if let boolValue = value as? Bool {
        function(object, selector, boolValue)
      } else if let number = value as? NSNumber {
        function(object, selector, number.boolValue)
      }
    case "q", "Q", "l", "L", "i", "I", "s", "S":
      typealias IntSetter = @convention(c) (AnyObject, Selector, Int64) -> Void
      guard let implementation = class_getMethodImplementation(type(of: object), selector) else {
        object.perform(selector, with: value)
        return
      }
      let function = unsafeBitCast(implementation, to: IntSetter.self)
      if let number = value as? NSNumber {
        function(object, selector, number.int64Value)
      } else if let intValue = value as? Int64 {
        function(object, selector, intValue)
      } else if let intValue = value as? Int {
        function(object, selector, Int64(intValue))
      }
    case "d", "f":
      typealias DoubleSetter = @convention(c) (AnyObject, Selector, Double) -> Void
      guard let implementation = class_getMethodImplementation(type(of: object), selector) else {
        object.perform(selector, with: value)
        return
      }
      let function = unsafeBitCast(implementation, to: DoubleSetter.self)
      if let number = value as? NSNumber {
        function(object, selector, number.doubleValue)
      } else if let doubleValue = value as? Double {
        function(object, selector, doubleValue)
      } else if let intValue = value as? Int64 {
        function(object, selector, Double(intValue))
      }
    case _ where argumentType.hasPrefix("@"):
      object.perform(selector, with: value)
    default:
      if let boolValue = value as? Bool {
        typealias BoolSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
        guard let implementation = class_getMethodImplementation(type(of: object), selector) else {
          object.perform(selector, with: value)
          return
        }
        let function = unsafeBitCast(implementation, to: BoolSetter.self)
        function(object, selector, boolValue)
      } else if let number = value as? NSNumber {
        typealias IntSetter = @convention(c) (AnyObject, Selector, Int64) -> Void
        guard let implementation = class_getMethodImplementation(type(of: object), selector) else {
          object.perform(selector, with: value)
          return
        }
        let function = unsafeBitCast(implementation, to: IntSetter.self)
        function(object, selector, number.int64Value)
      } else {
        object.perform(selector, with: value)
      }
    }
  }

  private static func stringValue(from object: NSObject, selectors: [String]) -> String? {
    for name in selectors {
      let selector = NSSelectorFromString(name)
      if object.responds(to: selector), let value = object.perform(selector)?.takeUnretainedValue() as? String {
        return value
      }
    }
    return nil
  }

  private static func boolValue(from object: NSObject, selectors: [String]) -> Bool? {
    for name in selectors {
      let selector = NSSelectorFromString(name)
      if object.responds(to: selector), let method = class_getInstanceMethod(type(of: object), selector) {
        let returnTypeCString: UnsafeMutablePointer<Int8>? = method_copyReturnType(method)
        guard let returnTypeCString else {
          continue
        }
        defer { free(returnTypeCString) }

        let returnType = String(cString: returnTypeCString)
        if returnType == "B" || returnType == "c" {
          typealias BoolFunction = @convention(c) (AnyObject, Selector) -> Bool
          let methodPointer = object.method(for: selector)
          let function = unsafeBitCast(methodPointer, to: BoolFunction.self)
          return function(object, selector)
        }
        if returnType == "@" {
          if let value = object.perform(selector)?.takeUnretainedValue() as? NSNumber {
            return value.boolValue
          }
          if let value = object.perform(selector)?.takeUnretainedValue() as? NSString {
            return value.boolValue
          }
        }
      }
    }
    return nil
  }
}
