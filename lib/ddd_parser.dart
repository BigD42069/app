import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Quelle der DDD-Datei – Fahrerkarte oder Fahrzeuggerät.
enum DddSource {
  card,
  vu,
}

extension on DddSource {
  String get asNativeValue => this == DddSource.card ? 'card' : 'vu';
}

/// Ergebnisobjekt nach einem nativen Parse-Durchlauf.
class DddParseResult {
  DddParseResult({
    required this.status,
    required this.verified,
    this.jsonString,
    this.verificationLog,
    this.errorDetails,
  });

  factory DddParseResult.fromMap(Map<String, dynamic> map) {
    return DddParseResult(
      status: map['status'] as String? ?? 'error',
      verified: map['verified'] as bool? ?? false,
      jsonString: map['json'] as String?,
      verificationLog: map['verificationLog'] as String?,
      errorDetails: map['errorDetails'] as String?,
    );
  }

  /// Status-Flag vom nativen Parser (`ok`, `error`, `cancelled`).
  final String status;

  /// Status der Signaturprüfung aus dem nativen Parser.
  final bool verified;

  /// Rohes JSON (vom nativen Code geliefert).
  final String? jsonString;

  /// Detailierter Verifikationslog, sofern angefordert.
  final String? verificationLog;

  /// Fehlermeldung bei `status == error`.
  final String? errorDetails;

  bool get isOk => status == 'ok';
  bool get isCancelled => status == 'cancelled';

  /// Versucht das JSON hübsch einzurücken. Fällt andernfalls auf den Roh-String zurück.
  String? get prettyJson {
    final raw = jsonString;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }
}

/// Flutter-seitige Helferklasse für den Tachograph-Parser.
class DddParser {
  DddParser._();

  /// Singleton-Instanz für bequemen Zugriff im UI-Code.
  static final DddParser instance = DddParser._();

  static const MethodChannel _channel = MethodChannel('tachograph_native');

  /// Startet den nativen Parser mit den angegebenen Daten.
  Future<DddParseResult> parse({
    required Uint8List data,
    DddSource source = DddSource.card,
    String? pks1Dir,
    String? pks2Dir,
    bool strictMode = false,
    Duration? timeout,
  }) async {
    final args = <String, dynamic>{
      'payload': data,
      'source': source.asNativeValue,
      'pks1Dir': pks1Dir ?? '',
      'pks2Dir': pks2Dir ?? '',
      'strictMode': strictMode,
    };
    if (timeout != null) {
      args['timeoutMs'] = timeout.inMilliseconds;
    }

    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('parseDdd', args);
      if (map == null) {
        throw const ParserException('parser-error', 'Leere Antwort vom nativen Parser erhalten');
      }
      return DddParseResult.fromMap(map);
    } on PlatformException catch (error) {
      throw ParserException(
        error.code,
        error.message ?? 'Native Parser-Exception',
        error.details,
      );
    }
  }

  /// Bricht einen laufenden Parse-Lauf (falls vorhanden) ab.
  Future<void> cancelActiveParse() async {
    try {
      await _channel.invokeMethod<void>('cancelActiveParse');
    } on PlatformException catch (error) {
      throw ParserException(
        error.code,
        error.message ?? 'Abbrechen des Parsers fehlgeschlagen',
        error.details,
      );
    }
  }
}

/// Einheitlicher Fehler-Typ für Parser-Probleme.
class ParserException implements Exception {
  const ParserException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'ParserException($code, $message)';
}
