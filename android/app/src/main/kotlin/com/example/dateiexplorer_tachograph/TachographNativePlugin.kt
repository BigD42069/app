package com.example.dateiexplorer_tachograph

import go.Seq
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import mobile.NativeError
import mobile.ParseOptions
import mobile.Parser

private const val CHANNEL_NAME = "tachograph_native"

class TachographNativePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var parser: Parser? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Seq.setContext(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        parser = Parser.newParser()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        parser?.close()
        parser = null
        Seq.destroy()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "parseDdd" -> handleParse(call, result)
            "cancelActiveParse" -> handleCancel(result)
            else -> result.notImplemented()
        }
    }

    private fun handleParse(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
            ?: run {
                result.error("invalid-arguments", "Missing arguments", null)
                return
            }

        val payload = args["payload"] as? ByteArray
        val source = args["source"] as? String
        val verify = args["verify"] as? Boolean ?: false
        val pksPath = args["pksPath"] as? String ?: ""
        val timeout = (args["timeoutMs"] as? Number)?.toLong() ?: 0L

        if (payload == null || source == null) {
            result.error("invalid-arguments", "payload and source are required", null)
            return
        }

        val parser = parser
        if (parser == null) {
            result.error("parser-error", "Parser not initialised", null)
            return
        }

        try {
            val options = ParseOptions().apply {
                setSource(source)
                setVerify(verify)
                setPKSPath(pksPath)
                setTimeoutMs(timeout)
            }
            val parseResult = parser.parseDdd(payload, options)
            val response = hashMapOf<String, Any?>(
                "status" to parseResult.status(),
                "json" to parseResult.json().orEmpty().ifEmpty { null },
                "verificationLog" to parseResult.verificationLog().orEmpty().ifEmpty { null },
                "errorDetails" to parseResult.errorDetails().orEmpty().ifEmpty { null },
            )
            result.success(response)
        } catch (error: NativeError) {
            result.error(error.code(), error.message, null)
        } catch (throwable: Throwable) {
            result.error("parser-error", throwable.message ?: "Unexpected native failure", null)
        }
    }

    private fun handleCancel(result: Result) {
        parser?.cancelActiveParse()
        result.success(null)
    }
}

private fun mobile.ParseResult.status(): String = getStatus()

private fun mobile.ParseResult.json(): String? = getJson()

private fun mobile.ParseResult.verificationLog(): String? = getVerificationLog()

private fun mobile.ParseResult.errorDetails(): String? = getErrorDetails()
