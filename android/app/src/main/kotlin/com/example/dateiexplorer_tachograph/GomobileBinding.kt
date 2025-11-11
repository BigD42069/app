package com.example.dateiexplorer_tachograph

import android.content.Context
import android.util.Log
import java.lang.IllegalStateException
import java.lang.reflect.Constructor
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method

private const val LOG_TAG = "TachographNative"

/**
 * Thin reflective wrapper around the gomobile-generated classes. The actual
 * mobile bindings are optional at compile time – this helper verifies their
 * presence at runtime and exposes a small API surface for the plugin.
 */
internal class GomobileBinding private constructor(
    private val parserInstance: Any,
    private val parseMethod: Method,
    private val cancelMethod: Method?,
    private val closeMethod: Method?,
    private val parseOptionsCtor: Constructor<*>,
    private val setSourceMethod: Method?,
    private val setPks1DirMethod: Method?,
    private val setPks2DirMethod: Method?,
    private val setStrictModeMethod: Method?,
    private val setTimeoutMethod: Method?,
    private val parseResultStatus: Method?,
    private val parseResultJson: Method?,
    private val parseResultVerified: Method?,
    private val parseResultVerificationLog: Method?,
    private val parseResultErrorDetails: Method?,
    private val nativeErrorClass: Class<*>?,
    private val nativeErrorCode: Method?,
    private val nativeErrorMessage: Method?,
    private val seqDestroyMethod: Method?,
) {
    sealed class ParseOutcome {
        data class Success(val payload: Map<String, Any?>) : ParseOutcome()
        data class NativeFailure(val code: String, val message: String?) : ParseOutcome()
        data class UnexpectedFailure(val error: Throwable) : ParseOutcome()
    }

    fun parse(
        payload: ByteArray,
        source: String,
        pks1Dir: String,
        pks2Dir: String,
        strictMode: Boolean,
        timeoutMs: Long,
    ): ParseOutcome {
        val options = try {
            parseOptionsCtor.newInstance()
        } catch (error: ReflectiveOperationException) {
            return ParseOutcome.UnexpectedFailure(error)
        }

        try {
            setSourceMethod?.invoke(options, source)
        } catch (error: Throwable) {
            Log.w(LOG_TAG, "Failed to set source on ParseOptions", error)
        }
        try {
            setPks1DirMethod?.invoke(options, pks1Dir)
        } catch (error: Throwable) {
            Log.w(LOG_TAG, "Failed to set pks1Dir on ParseOptions", error)
        }
        try {
            setPks2DirMethod?.invoke(options, pks2Dir)
        } catch (error: Throwable) {
            Log.w(LOG_TAG, "Failed to set pks2Dir on ParseOptions", error)
        }
        try {
            setStrictModeMethod?.invoke(options, strictMode)
        } catch (error: Throwable) {
            Log.w(LOG_TAG, "Failed to set strictMode on ParseOptions", error)
        }
        if (timeoutMs > 0) {
            try {
                setTimeoutMethod?.invoke(options, timeoutMs)
            } catch (error: Throwable) {
                Log.w(LOG_TAG, "Failed to set timeout on ParseOptions", error)
            }
        }

        val result = try {
            parseMethod.invoke(parserInstance, payload, options)
        } catch (error: InvocationTargetException) {
            val cause = error.targetException ?: error
            if (nativeErrorClass?.isInstance(cause) == true) {
                val code = nativeErrorCode?.invoke(cause) as? String ?: "parser-error"
                val message = nativeErrorMessage?.invoke(cause) as? String ?: cause.message
                return ParseOutcome.NativeFailure(code, message)
            }
            return ParseOutcome.UnexpectedFailure(cause)
        } catch (error: ReflectiveOperationException) {
            return ParseOutcome.UnexpectedFailure(error)
        }

        val status = parseResultStatus?.invoke(result) as? String ?: "unknown"
        val json = (parseResultJson?.invoke(result) as? String).orEmpty()
        val verified = parseResultVerified?.invoke(result) as? Boolean ?: false
        val verificationLog = (parseResultVerificationLog?.invoke(result) as? String).orEmpty()
        val errorDetails = (parseResultErrorDetails?.invoke(result) as? String).orEmpty()

        val payloadMap = mapOf(
            "status" to status,
            "json" to json.ifEmpty { null },
            "verified" to verified,
            "verificationLog" to verificationLog.ifEmpty { null },
            "errorDetails" to errorDetails.ifEmpty { null },
        )
        return ParseOutcome.Success(payloadMap)
    }

    fun cancel() {
        try {
            cancelMethod?.invoke(parserInstance)
        } catch (error: Throwable) {
            Log.w(LOG_TAG, "Failed to cancel parser", error)
        }
    }

    fun close() {
        try {
            cancelMethod?.invoke(parserInstance)
        } catch (_: Throwable) {
            // Ignore
        }
        try {
            closeMethod?.invoke(parserInstance)
        } catch (_: Throwable) {
            // Ignore
        }
        try {
            seqDestroyMethod?.invoke(null)
        } catch (_: Throwable) {
            // Ignore
        }
    }

    companion object {
        fun tryCreate(context: Context): GomobileBinding? {
            val applicationContext = context.applicationContext
            val seqDestroy = initialiseSeq(applicationContext)

            val parserClass = try {
                Class.forName("mobile.Parser")
            } catch (_: ClassNotFoundException) {
                return null
            }

            val parserInstance = try {
                parserClass.getDeclaredConstructor().newInstance()
            } catch (_: NoSuchMethodException) {
                val factory = try {
                    parserClass.getMethod("newParser")
                } catch (error: NoSuchMethodException) {
                    throw IllegalStateException("Parser.newParser() factory missing", error)
                }
                factory.invoke(null)
            }

            val parseOptionsClass = Class.forName("mobile.ParseOptions")
            val parseResultClass = Class.forName("mobile.ParseResult")
            val nativeErrorClass = try {
                Class.forName("mobile.NativeError")
            } catch (_: ClassNotFoundException) {
                null
            }

            val parseMethod = parserClass.getMethod("parseDdd", ByteArray::class.java, parseOptionsClass)
            val cancelMethod = parserClass.methods.firstOrNull { it.name == "cancelActiveParse" && it.parameterCount == 0 }
            val closeMethod = parserClass.methods.firstOrNull { it.name == "close" && it.parameterCount == 0 }

            val parseOptionsCtor = parseOptionsClass.getDeclaredConstructor()
            val setSourceMethod = parseOptionsClass.findMethod("setSource", String::class.java)
            val setPks1DirMethod = parseOptionsClass.findMethod("setPKS1Dir", String::class.java)
            val setPks2DirMethod = parseOptionsClass.findMethod("setPKS2Dir", String::class.java)
            val setStrictModeMethod = parseOptionsClass.findMethod("setStrictMode", java.lang.Boolean.TYPE, java.lang.Boolean::class.java)
            val setTimeoutMethod = parseOptionsClass.findMethod("setTimeoutMs", java.lang.Long.TYPE, java.lang.Long::class.java)

            val parseResultStatus = parseResultClass.findMethod("getStatus")
            val parseResultJson = parseResultClass.findMethod("getJson")
            val parseResultVerified = parseResultClass.findMethod("getVerified")
            val parseResultVerificationLog = parseResultClass.findMethod("getVerificationLog")
            val parseResultErrorDetails = parseResultClass.findMethod("getErrorDetails")

            val nativeErrorCode = nativeErrorClass?.findMethod("getCode")
            val nativeErrorMessage = nativeErrorClass?.findMethod("getMessage")

            return GomobileBinding(
                parserInstance = parserInstance,
                parseMethod = parseMethod,
                cancelMethod = cancelMethod,
                closeMethod = closeMethod,
                parseOptionsCtor = parseOptionsCtor,
                setSourceMethod = setSourceMethod,
                setPks1DirMethod = setPks1DirMethod,
                setPks2DirMethod = setPks2DirMethod,
                setStrictModeMethod = setStrictModeMethod,
                setTimeoutMethod = setTimeoutMethod,
                parseResultStatus = parseResultStatus,
                parseResultJson = parseResultJson,
                parseResultVerified = parseResultVerified,
                parseResultVerificationLog = parseResultVerificationLog,
                parseResultErrorDetails = parseResultErrorDetails,
                nativeErrorClass = nativeErrorClass,
                nativeErrorCode = nativeErrorCode,
                nativeErrorMessage = nativeErrorMessage,
                seqDestroyMethod = seqDestroy,
            )
        }

        private fun initialiseSeq(context: Context): Method? {
            return try {
                val seqClass = Class.forName("go.Seq")
                val setContext = seqClass.getMethod("setContext", Context::class.java)
                setContext.invoke(null, context)
                seqClass.getMethod("destroy")
            } catch (_: ClassNotFoundException) {
                null
            } catch (error: ReflectiveOperationException) {
                Log.w(LOG_TAG, "Failed to initialise go.Seq runtime", error)
                null
            }
        }
    }
}

private fun Class<*>.findMethod(name: String, vararg candidateParamTypes: Class<*>?): Method? {
    if (candidateParamTypes.isEmpty()) {
        return try {
            getMethod(name)
        } catch (_: NoSuchMethodException) {
            null
        }
    }
    candidateParamTypes.filterNotNull().forEach { type ->
        try {
            return getMethod(name, type)
        } catch (_: NoSuchMethodException) {
            // Try next candidate
        }
    }
    return null
}
