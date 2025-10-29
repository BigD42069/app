import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const String kTransferFileName = 'ddd.ddd';

/// Repräsentiert einen einzelnen Tag aus der Tachographen-Datei.
class TachographDay {
  TachographDay({
    required this.date,
    required this.startOdometer,
    required this.endOdometer,
  });

  /// UTC-Datum (ohne Uhrzeit) des Fahrttages.
  final DateTime date;

  /// Kilometerstand zu Tagesbeginn.
  final int startOdometer;

  /// Kilometerstand zu Tagesende.
  final int endOdometer;

  /// Berechnete Tageskilometer. Berücksichtigt einen möglichen 24-Bit-Overflow
  /// des Tachographenzählers.
  int get distanceKm {
    final rawDiff = endOdometer - startOdometer;
    if (rawDiff >= 0) return rawDiff;
    // Odometer nutzt 24 Bit → nach 16.777.216 wird überlaufen.
    return (endOdometer + (1 << 24)) - startOdometer;
  }

  /// Liefert `true`, falls an diesem Tag Bewegungen aufgezeichnet wurden.
  bool get hasMovement => distanceKm > 0;
}

/// Lädt die zuletzt übertragene DDD-Datei und liefert daraus extrahierte Tage.
class TachographRepository {
  TachographRepository({TachographParser? parser})
      : _parser = parser ?? TachographParser();

  final TachographParser _parser;

  /// Öffnet die gespeicherte DDD-Datei (falls vorhanden) und parst deren Inhalt.
  Future<List<TachographDay>> loadDays() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$kTransferFileName');
    if (!await file.exists()) {
      return const [];
    }

    try {
      final bytes = await file.readAsBytes();
      final days = _parser.parse(bytes);
      // Nur Tage mit Bewegung anzeigen.
      return days.where((d) => d.hasMovement).toList(growable: false);
    } catch (e, st) {
      debugPrint('DDD parsing failed: $e');
      debugPrint('$st');
      throw FormatException('Die DDD-Datei konnte nicht verarbeitet werden.');
    }
  }
}

/// Liest die Binärstruktur einer DDD-Datei und extrahiert Tagesinformationen.
class TachographParser {
  static const int _maxReasonableDistanceKm = 2000;

  List<TachographDay> parse(Uint8List bytes) {
    final found = <DateTime, TachographDay>{};

    void addDay(TachographDay day) {
      final existing = found[day.date];
      if (existing == null || day.distanceKm > existing.distanceKm) {
        found[day.date] = day;
      }
    }

    final blocks = _parseTlvBlocks(bytes);
    if (blocks.isEmpty) {
      _extractDays(bytes, addDay);
    } else {
      for (final block in blocks) {
        _extractDays(block, addDay);
      }
    }

    final days = found.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return days;
  }

  List<Uint8List> _parseTlvBlocks(Uint8List bytes) {
    final blocks = <Uint8List>[];
    int index = 0;
    while (index + 3 <= bytes.length) {
      final int tag = bytes[index];
      final int length = (bytes[index + 1] << 8) | bytes[index + 2];
      index += 3;

      if (length <= 0 || index + length > bytes.length) {
        // Abbruch bei ungültigen Längen.
        return const [];
      }

      // Nur Datenblöcke im Bereich 0xC0..0xEF sind relevant.
      if (tag >= 0xC0 && tag <= 0xEF) {
        blocks.add(Uint8List.sublistView(bytes, index, index + length));
      }

      index += length;
    }
    return blocks;
  }

  void _extractDays(Uint8List data, void Function(TachographDay) emit) {
    for (int i = 0; i <= data.length - 8; i++) {
      final int rawDate = (data[i] << 8) | data[i + 1];
      final DateTime? date = _decodeDate(rawDate);
      if (date == null) continue;

      final int? start = _readUInt24(data, i + 2);
      final int? end = _readUInt24(data, i + 5);
      if (start == null || end == null) continue;

      final tachographDay = TachographDay(
        date: date,
        startOdometer: start,
        endOdometer: end,
      );

      final distance = tachographDay.distanceKm;
      if (distance <= 0 || distance > _maxReasonableDistanceKm) {
        continue;
      }

      emit(tachographDay);
      // Record-Strukturen sind deutlich länger als 8 Bytes → etwas vorspulen.
      i += 6;
    }
  }

  DateTime? _decodeDate(int raw) {
    final year = ((raw >> 9) & 0x7F) + 1985;
    final month = (raw >> 5) & 0x0F;
    final day = raw & 0x1F;

    if (month == 0 || month > 12) return null;
    if (day == 0 || day > 31) return null;

    try {
      return DateTime.utc(year, month, day);
    } catch (_) {
      return null;
    }
  }

  int? _readUInt24(Uint8List data, int offset) {
    if (offset + 3 > data.length) return null;
    return (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
  }
}

/// Globale Repository-Instanz, damit UI-Widgets unkompliziert darauf zugreifen.
final tachographRepository = TachographRepository();
