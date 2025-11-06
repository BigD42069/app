package com.example.dateiexplorer_tachograph

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

private const val CHANNEL_NAME = "tachograph_native"

class TachographNativePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var binding: GomobileBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        this.binding = GomobileBinding.tryCreate(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        this.binding?.close()
        this.binding = null
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
        if (args == null) {
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

        val mobileBinding = binding
        if (mobileBinding == null) {
            result.error(
                "missing-native-lib",
                "Gomobile-Bindings wurden nicht eingebunden. Bitte AAR/XCFramework laut docs/gomobile_tooling.md bauen und in das Projekt einbinden.",
                null,
            )
            return
        }

        when (val outcome = mobileBinding.parse(payload, source, verify, pksPath, timeout)) {
            is GomobileBinding.ParseOutcome.Success -> result.success(outcome.payload)
            is GomobileBinding.ParseOutcome.NativeFailure -> result.error(outcome.code, outcome.message, null)
            is GomobileBinding.ParseOutcome.UnexpectedFailure -> result.error(
                "parser-error",
                outcome.error.message ?: "Unexpected native failure",
                null,
            )
        }
    }

    private fun handleCancel(result: Result) {
        binding?.cancel()
        result.success(null)
    }
}
