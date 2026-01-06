package com.example.dateiexplorer_tachograph

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import mobile.Mobile
import mobile.Parser
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

private const val CHANNEL_NAME = "tachograph_native"
private const val TAG = "TachographNative"
private const val PKS_ASSET_PREFIX = "assets/pkg/certificates"
private const val PKS1_REQUIRED_FILE = "EC_PK.bin"
private const val PKS2_REQUIRED_FILE = "ERCA Gen2 (1) Root Certificate.bin"

/**
 * Native Bridge auf die gomobile-Bibliothek (mobile.aar).
 */
class TachographNativePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var parser: Parser? = null
    private var parserPks1: String? = null
    private var parserPks2: String? = null
    private lateinit var context: Context
    private lateinit var flutterAssets: FlutterPlugin.FlutterAssets
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        context = binding.applicationContext
        flutterAssets = binding.flutterAssets
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        parser = null
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "parseDdd" -> handleParse(call, result)
            "cancelActiveParse" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun handleParse(call: MethodCall, result: Result) {
        val payload = call.argument<ByteArray>("payload")
        if (payload == null || payload.isEmpty()) {
            result.error("invalid-arguments", "payload missing", null)
            return
        }

        val source = (call.argument<String>("source") ?: "card").lowercase()
        val mode = if (source == "vu") "vu" else "card"
        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 0).toLong()
        val pks1Dir = call.argument<String>("pks1Dir")
        val pks2Dir = call.argument<String>("pks2Dir")

        executor.execute {
            try {
                val p = ensureParser(pks1Dir, pks2Dir)
                val parseResult = if (timeoutMs > 0) {
                    p.parseWithTimeout(payload, mode, timeoutMs)
                } else if (mode == "vu") {
                    p.parseVehicleUnit(payload)
                } else {
                    p.parseCard(payload)
                }

                val payloadJson = parseResult.payloadJSON
                val map = mapOf(
                    "status" to "ok",
                    "json" to payloadJson.takeIf { it.isNotEmpty() },
                    "verified" to parseResult.verified,
                    "verificationLog" to null,
                    "errorDetails" to null,
                )
                mainHandler.post { result.success(map) }
            } catch (err: Exception) {
                Log.e(TAG, "parse failed (mode=$mode)", err)
                mainHandler.post { result.error("parser-error", err.message, null) }
            }
        }
    }

    private fun ensureParser(pks1Override: String?, pks2Override: String?): Parser {
        val pks1 = resolvePksDir(pks1Override, "pks1")
        val pks2 = resolvePksDir(pks2Override, "pks2")

        val existing = parser
        if (existing != null && parserPks1 == pks1.absolutePath && parserPks2 == pks2.absolutePath) {
            return existing
        }

        val created = Mobile.createParser(pks1.absolutePath, pks2.absolutePath)
        parser = created
        parserPks1 = pks1.absolutePath
        parserPks2 = pks2.absolutePath
        return created
    }

    private fun resolvePksDir(overridePath: String?, name: String): File {
        if (!overridePath.isNullOrBlank()) {
            val dir = File(overridePath)
            if (!dir.exists() || !dir.isDirectory) {
                throw IllegalStateException("PKS dir not found: $overridePath")
            }
            return dir
        }

        val targetDir = File(context.filesDir, name)
        if (!targetDir.exists() || targetDir.list()?.isEmpty() != false) {
            val assetDir = flutterAssets.getAssetFilePathByName("$PKS_ASSET_PREFIX/$name")
            copyAssetDir(context, assetDir, targetDir)
        }
        requiredFileFor(name)?.let { ensureRequiredFile(targetDir, it) }
        if (!targetDir.exists() || targetDir.list()?.isEmpty() != false) {
            throw IllegalStateException("PKS dir not found: $name")
        }
        return targetDir
    }

    private fun requiredFileFor(name: String): String? {
        return when (name) {
            "pks1" -> PKS1_REQUIRED_FILE
            "pks2" -> PKS2_REQUIRED_FILE
            else -> null
        }
    }

    private fun ensureRequiredFile(targetDir: File, requiredFile: String) {
        val required = File(targetDir, requiredFile)
        if (required.exists()) {
            return
        }
        val underscored = requiredFile.replace(" ", "_")
        if (underscored != requiredFile) {
            val candidate = File(targetDir, underscored)
            if (candidate.exists()) {
                candidate.copyTo(required, overwrite = true)
            }
        }
    }

    private fun copyAssetDir(context: Context, assetDir: String, targetDir: File) {
        val assets = try {
            context.assets.list(assetDir)
        } catch (err: IOException) {
            throw IllegalStateException("Failed to list assets for $assetDir", err)
        } ?: throw IllegalStateException("Asset dir not found: $assetDir")

        if (assets.isEmpty()) {
            throw IllegalStateException("Asset dir empty: $assetDir")
        }

        targetDir.mkdirs()
        for (name in assets) {
            val inPath = "$assetDir/$name"
            val outFile = File(targetDir, name)
            val children = try {
                context.assets.list(inPath)
            } catch (err: IOException) {
                null
            }
            if (children != null && children.isNotEmpty()) {
                copyAssetDir(context, inPath, outFile)
            } else if (!outFile.exists()) {
                context.assets.open(inPath).use { input ->
                    outFile.outputStream().use { output -> input.copyTo(output) }
                }
            }
        }
    }
}
