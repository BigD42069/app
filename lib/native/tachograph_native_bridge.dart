import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Name des MethodChannels, über den die nativen gomobile-Bindings erreichbar
/// sind.
const String kTachographChannelName = 'tachograph_native';

/// Schnittstelle zur nativen Tachographenbibliothek.
class TachographNativeBridge {
  TachographNativeBridge({
    MethodChannel? channel,
    this.defaultTimeout = const Duration(seconds: 30),
  }) : _channel = channel ?? const MethodChannel(kTachographChannelName);

  final MethodChannel _channel;

  /// Fallback-Timeout, falls der Aufrufer keines angibt.
  final Duration defaultTimeout;

  /// Führt das native Parsing der DDD-Datei aus.
  ///
  /// Der Aufruf blockiert nicht den UI-Thread. Die Parameter entsprechen dem
  /// dokumentierten Wrapper-Kontrakt (siehe docs/flutter_plugin_bridge.md).
  Future<TachographParseResponse> parseDdd({
    required Uint8List payload,
    required TachographBindingTarget source,
    required bool verify,
    required String pksPath,
    Duration? timeout,
  }) async {
    final Duration effectiveTimeout = timeout ?? defaultTimeout;

    final Map<String, Object?> arguments = <String, Object?>{
      'payload': payload,
      'source': source.name,
      'verify': verify,
      'pksPath': pksPath,
      'timeoutMs': effectiveTimeout.inMilliseconds,
    };

    try {
      final Map<String, Object?>? response = await _channel
          .invokeMapMethod<String, Object?>('parseDdd', arguments)
          .timeout(effectiveTimeout, onTimeout: () {
        throw const TachographNativeException(
          code: TachographNativeErrorCode.timeout,
          message: 'Die native Analyse hat das definierte Timeout überschritten.',
        );
      });

      if (response == null) {
        throw const TachographNativeException(
          code: TachographNativeErrorCode.protocol,
          message: 'Es wurde keine Antwort vom nativen Parser zurückgegeben.',
        );
      }

      final rawStatus = response['status'] as String?;
      final status = tachographNativeStatusFromName(rawStatus);

      switch (status) {
        case TachographNativeStatus.ok:
          final json = response['json'] as String?;
          if (json == null) {
            throw const TachographNativeException(
              code: TachographNativeErrorCode.protocol,
              message: 'Erfolg ohne JSON-Payload vom nativen Parser erhalten.',
            );
          }
          return TachographParseResponse(
            status: status,
            json: json,
            verificationLog: response['verificationLog'] as String?,
          );
        case TachographNativeStatus.cancelled:
          throw const TachographNativeException(
            code: TachographNativeErrorCode.cancelled,
            message: 'Der Vorgang wurde abgebrochen.',
          );
        case TachographNativeStatus.error:
        case TachographNativeStatus.unknown:
          final message = response['errorDetails'] as String? ??
              'Die native Analyse konnte nicht abgeschlossen werden.';
          throw TachographNativeException(
            code: TachographNativeErrorCode.parserError,
            message: message,
          );
      }
      throw const TachographNativeException(
        code: TachographNativeErrorCode.protocol,
        message: 'Unbekannter nativer Statuswert.',
      );
    } on PlatformException catch (error) {
      final TachographNativeErrorCode code;
      switch (error.code) {
        case 'timeout':
          code = TachographNativeErrorCode.timeout;
          break;
        case 'cancelled':
          code = TachographNativeErrorCode.cancelled;
          break;
        case 'missing-native-lib':
          code = TachographNativeErrorCode.unavailable;
          break;
        case 'invalid-arguments':
          code = TachographNativeErrorCode.protocol;
          break;
        default:
          code = TachographNativeErrorCode.parserError;
      }
      throw TachographNativeException(
        code: code,
        message: error.message ?? 'Native Parser meldet einen Fehler.',
      );
    }
  }

  /// Signalisiert der nativen Seite, dass ein laufender Parse-Vorgang beendet
  /// werden soll.
  Future<void> cancelActiveParse() async {
    await _channel.invokeMethod<void>('cancelActiveParse');
  }
}

/// Zielquelle der DDD-Datei.
enum TachographBindingTarget { vu, card }

/// Statuswerte, die vom nativen Code gemeldet werden können.
enum TachographNativeStatus { ok, error, cancelled, unknown }

TachographNativeStatus tachographNativeStatusFromName(String? value) {
  return TachographNativeStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => TachographNativeStatus.unknown,
  );
}

/// Ergebnis eines erfolgreichen nativen Parse-Laufs.
class TachographParseResponse {
  const TachographParseResponse({
    required this.status,
    required this.json,
    this.verificationLog,
  });

  final TachographNativeStatus status;
  final String json;
  final String? verificationLog;
}

/// Fehlerkategorien der nativen Brücke.
enum TachographNativeErrorCode {
  parserError,
  timeout,
  cancelled,
  protocol,
  unavailable,
}

/// Strukturierte Exception für Brücken-Fehler.
class TachographNativeException implements Exception {
  const TachographNativeException({
    required this.code,
    required this.message,
  });

  final TachographNativeErrorCode code;
  final String message;

  @override
  String toString() => 'TachographNativeException($code, $message)';
}
