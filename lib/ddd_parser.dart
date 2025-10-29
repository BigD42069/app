import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Repräsentiert einen einzelnen Tag aus einer DDD-Datei inklusive
/// zusammengefasster Aktivitätszeiten.
class DddDayEntry {
  DddDayEntry({
    required this.date,
    required this.driving,
    required this.work,
    required this.availability,
    required this.rest,
  });

  final DateTime date;
  final Duration driving;
  final Duration work;
  final Duration availability;
  final Duration rest;

  /// Ein Tag wird nur dann in der Liste angezeigt, wenn Fahrzeit vorhanden ist.
  bool get hasMovement => driving > Duration.zero;

  /// Formatiert das Datum im deutschen Format (TT.MM.JJJJ).
  String get formattedDate =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year.toString().padLeft(4, '0')}';

  /// Kompakte Beschreibung für die Listenansicht.
  String buildSummary() {
    final parts = <String>['Fahrzeit ${_formatDuration(driving)}'];
    if (work > Duration.zero) {
      parts.add('Arbeit ${_formatDuration(work)}');
    }
    if (availability > Duration.zero) {
      parts.add('Bereitschaft ${_formatDuration(availability)}');
    }
    if (rest > Duration.zero) {
      parts.add('Ruhe ${_formatDuration(rest)}');
    }
    return parts.join(' · ');
  }

  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final buffer = StringBuffer();
    if (hours > 0) buffer.write('${hours}h');
    if (minutes > 0 || hours == 0) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write('${minutes}m');
    }
    return buffer.toString();
  }
}

/// Kümmert sich darum, eine gespeicherte DDD-Datei zu finden und auszuwerten.
class DddFileRepository {
  const DddFileRepository();

  /// Lädt aus der zuletzt übertragenen DDD-Datei alle Tage mit Fahrzeugbewegung.
  Future<List<DddDayEntry>> loadDrivingDays({
    List<String> preferredFileNames = const ['ddd.ddd'],
  }) async {
    final file = await _locateLatestFile(preferredFileNames: preferredFileNames);
    if (file == null) {
      return [];
    }

    try {
      final bytes = await file.readAsBytes();
      final entries = DddParser.parse(bytes);
      final filtered = entries.where((e) => e.hasMovement).toList();
      filtered.sort((a, b) => b.date.compareTo(a.date));
      return filtered;
    } catch (e, st) {
      debugPrint('Fehler beim Lesen der DDD-Datei ${file.path}: $e');
      debugPrint('$st');
      return [];
    }
  }

  Future<File?> _locateLatestFile({
    required List<String> preferredFileNames,
  }) async {
    final directory = await getApplicationDocumentsDirectory();

    // 1) Bevorzugte Dateinamen (z. B. die vom Transfer verwendete ddd.ddd).
    for (final name in preferredFileNames) {
      final candidate = File('${directory.path}/$name');
      if (await candidate.exists()) {
        return candidate;
      }
    }

    // 2) Andernfalls: neueste *.ddd-Datei aus dem Dokumentenordner.
    final files = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.ddd')) {
        files.add(entity);
      }
    }
    if (files.isEmpty) return null;

    File? newest;
    DateTime? newestTime;
    for (final file in files) {
      try {
        final stat = await file.stat();
        final modified = stat.modified;
        if (newest == null || modified.isAfter(newestTime!)) {
          newest = file;
          newestTime = modified;
        }
      } catch (e) {
        debugPrint('Kann Änderungsdatum für ${file.path} nicht lesen: $e');
      }
    }
    return newest;
  }
}

/// Einfache Auswertung der DailyActivity-Blöcke innerhalb einer DDD-Datei.
///
/// Die Implementierung sucht nach Tagesdatensätzen, indem sie nach gültigen
/// Datumscodes sucht (gemäß Tachograph-Spezifikation: 2 Bytes mit Bitfeldern für
/// Jahr/Monat/Tag). Direkt danach werden 360 Bytes mit 2-Bit Aktivitätscodes
/// erwartet – das entspricht 24 Stunden à 60 Minuten. Diese Blöcke liefern
/// Informationen über Fahr-, Arbeits-, Bereitschafts- und Ruhezeiten.
class DddParser {
  const DddParser._();

  static const int _activityBytesPerDay = 360; // 1440 Minuten * 2 Bit

  static List<DddDayEntry> parse(Uint8List bytes) {
    final result = <DateTime, DddDayEntry>{};

    for (int i = 0; i + 1 + _activityBytesPerDay <= bytes.length; i++) {
      final rawDate = (bytes[i] << 8) | bytes[i + 1];
      final day = rawDate & 0x1F; // Bits 0..4
      final month = (rawDate >> 5) & 0x0F; // Bits 5..8
      final yearOffset = (rawDate >> 9) & 0x7F; // Bits 9..15
      final year = 1985 + yearOffset;

      if (!_isValidDate(year, month, day)) {
        continue;
      }

      final date = DateTime(year, month, day);
      final blockStart = i + 2;
      final blockEnd = blockStart + _activityBytesPerDay;
      if (blockEnd > bytes.length) {
        break;
      }

      final activityBlock = bytes.sublist(blockStart, blockEnd);
      final summary = _summarizeActivities(activityBlock);

      if (!summary.hasAnyActivity) {
        continue; // komplett leer -> uninteressant
      }

      final entry = DddDayEntry(
        date: date,
        driving: Duration(minutes: summary.drivingMinutes),
        work: Duration(minutes: summary.workMinutes),
        availability: Duration(minutes: summary.availabilityMinutes),
        rest: Duration(minutes: summary.restMinutes),
      );

      final existing = result[date];
      if (existing == null ||
          entry.driving > existing.driving ||
          (entry.driving == existing.driving &&
              entry.work > existing.work)) {
        result[date] = entry;
      }

      // Wir springen zum Ende des Blocks, um Dopplungen zu vermeiden.
      i = max(i, blockEnd - 1);
    }

    return result.values.toList();
  }

  static bool _isValidDate(int year, int month, int day) {
    if (year < 1985 || year > 2100) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    try {
      DateTime(year, month, day);
      return true;
    } catch (_) {
      return false;
    }
  }

  static _ActivitySummary _summarizeActivities(Uint8List block) {
    var rest = 0;
    var availability = 0;
    var work = 0;
    var driving = 0;

    for (final byte in block) {
      for (int shift = 6; shift >= 0; shift -= 2) {
        final state = (byte >> shift) & 0x03;
        switch (state) {
          case 0x00:
            rest++;
            break;
          case 0x01:
            availability++;
            break;
          case 0x02:
            work++;
            break;
          case 0x03:
            driving++;
            break;
        }
      }
    }

    return _ActivitySummary(
      restMinutes: rest,
      availabilityMinutes: availability,
      workMinutes: work,
      drivingMinutes: driving,
    );
  }
}

class _ActivitySummary {
  const _ActivitySummary({
    required this.restMinutes,
    required this.availabilityMinutes,
    required this.workMinutes,
    required this.drivingMinutes,
  });

  final int restMinutes;
  final int availabilityMinutes;
  final int workMinutes;
  final int drivingMinutes;

  bool get hasAnyActivity =>
      restMinutes > 0 ||
      availabilityMinutes > 0 ||
      workMinutes > 0 ||
      drivingMinutes > 0;
}
