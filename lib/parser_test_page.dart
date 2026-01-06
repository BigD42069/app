import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'calendar_events_store.dart';
import 'ddd_parser.dart';

/// Seite zum manuellen Testen des Tachograph-Parsers innerhalb der App.
class ParserTestPage extends StatefulWidget {
  const ParserTestPage({super.key});

  @override
  State<ParserTestPage> createState() => _ParserTestPageState();
}

class _ParserTestPageState extends State<ParserTestPage> {
  // Cache, damit der erste Ladevorgang nicht jedes Mal wiederholt wird.
  static Future<_ParserTestOutcome>? _cached;
  late final Future<_ParserTestOutcome> _future = _cached ??= _load();

  Future<_ParserTestOutcome> _load() async {
    final rawJson = await _loadRawJson();

    // JSON-Parsing im Hintergrund, um UI-Jank zu vermeiden.
    final parsed = await compute(_parseJsonAndSummary, rawJson);
    final summary = _ParserSummary.fromMap(parsed['summary'] as Map<String, dynamic>);
    final locks = (parsed['locks'] as List<dynamic>? ?? [])
        .map((e) => _CompanyLock.fromMap(e as Map<String, dynamic>))
        .toList();
    final driverActivities = (parsed['driverActivities'] as List<dynamic>? ?? [])
        .map((e) => _DriverActivity.fromMap(e as Map<String, dynamic>))
        .toList();
    final eventsAndFaults = (parsed['eventsAndFaults'] as List<dynamic>? ?? [])
        .map((e) => _EventsAndFaults.fromMap(e as Map<String, dynamic>))
        .toList();
    final technicalData = (parsed['technicalData'] as List<dynamic>? ?? [])
        .map((e) => _TechnicalData.fromMap(e as Map<String, dynamic>))
        .toList();

    return _ParserTestOutcome(
      summary: summary,
      locks: locks,
      driverActivities: driverActivities,
      technicalData: technicalData,
      eventsAndFaults: eventsAndFaults,
    );
  }

  Future<String> _loadRawJson() async {
    const dddAsset = 'assets/Example_files/LRO.DDD';
    try {
      final byteData = await rootBundle.load(dddAsset);
      final payload = byteData.buffer.asUint8List();
      final result = await DddParser.instance.parse(
        data: payload,
        source: DddSource.vu,
        strictMode: false,
      );
      final raw = result.jsonString;
      debugPrint(
        'ParserTest: DDD parse (vu) status=${result.status} '
        'verified=${result.verified} jsonLen=${raw?.length ?? 0}',
      );
      if (result.isOk && raw != null && raw.isNotEmpty) {
        return raw;
      }
      throw Exception(
        'DDD parse failed (vu): status=${result.status} json empty=${raw == null || raw.isEmpty}',
      );
    } on ParserException catch (err) {
      throw Exception('DDD parse failed (vu): ${err.code} ${err.message}');
    } catch (err) {
      throw Exception('DDD parse failed (vu): $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parsertest'),
      ),
      body: SafeArea(
        child: FutureBuilder<_ParserTestOutcome>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CupertinoActivityIndicator());
            }

            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error?.toString() ?? 'Unbekannter Fehler';
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 40, color: cs.error),
                      const SizedBox(height: 12),
                      Text(
                        'Datei konnte nicht geladen werden',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }

            final outcome = snapshot.requireData;
            final s = outcome.summary;
            final locks = outcome.locks;

            // Kalender-Daten aktualisieren (für die eigentliche App-Ansicht).
            final dayActivities = outcome.driverActivities
                .map((da) {
                  final parsedDate = _parseDateLocal(da.dayOriginal);
                  if (parsedDate == null) return null;
                  return DayActivity(
                    date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
                    rawDate: da.dayOriginal,
                    midnightOdometer: da.midnightOdometer,
                    cards: da.cardRows
                        .map(
                          (r) => CardRow(
                            firstName: r.firstName,
                            lastName: r.lastName,
                            slot: r.cardSlot,
                            type: r.cardType,
                            country: r.cardIssuingCountry,
                            number: r.cardNumber,
                            expiry: r.cardExpiry,
                            insertion: r.cardInsertion,
                            withdrawal: r.cardWithdrawal,
                            odoInsertion: r.odoInsertion,
                            odoWithdrawal: r.odoWithdrawal,
                            prevNation: r.prevNation,
                            prevPlate: r.prevPlate,
                            prevWithdrawal: r.prevCardWithdrawal,
                          ),
                        )
                        .toList(),
                    activities: da.activityRows
                        .map(
                          (a) => ActivityRow(
                            time: a.time,
                            cardPresent: a.cardPresent,
                            team: a.team,
                            role: a.role,
                            activity: a.activity,
                          ),
                        )
                        .toList(),
                    places: da.placeRows
                        .map(
                          (p) => PlaceRow(
                            cardType: p.cardType,
                            cardCountry: p.cardCountry,
                            cardNumber: p.cardNumber,
                            entryTime: p.entryTime,
                            country: p.country,
                            region: p.region,
                            odometer: p.odometer,
                            entryType: p.entryType,
                            gpsTime: p.gpsTime,
                            lat: p.lat,
                            lon: p.lon,
                          ),
                        )
                        .toList(),
                    gnss: da.gnssRows
                        .map(
                          (g) => GnssRow(
                            cardType: g.cardType,
                            cardCountry: g.cardCountry,
                            cardNumber: g.cardNumber,
                            time: g.time,
                            gpsTime: g.gpsTime,
                            lat: g.lat,
                            lon: g.lon,
                          ),
                        )
                        .toList(),
                    loads: da.loadRows
                        .map(
                          (l) => LoadRow(
                            cardType: l.cardType,
                            cardCountry: l.cardCountry,
                            cardNumber: l.cardNumber,
                            time: l.time,
                            operationType: l.operationType,
                            gpsTime: l.gpsTime,
                            lat: l.lat,
                            lon: l.lon,
                            odometer: l.odometer,
                          ),
                        )
                        .toList(),
                  );
                })
                .whereType<DayActivity>()
                .toList();
            final eventBundles = _buildEventBundles(outcome.eventsAndFaults);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              calendarEventsStore.setActivities(dayActivities);
              calendarEventsStore.setEventBundles(eventBundles);
            });

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Parsertest',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Fahrzeugidentifikationsnummer', value: s.vin),
                      _InfoRow(label: 'Kennzeichen', value: s.plate),
                      _InfoRow(label: 'Aktuelle Zeit', value: s.currentTime),
                      _InfoRow(label: 'Startzeit (min_downloadable_time)', value: s.periodStart),
                      _InfoRow(label: 'Endzeitpunkt (max_downloadable_time)', value: s.periodEnd),
                      _InfoRow(label: 'Status der Karteneinschübe', value: s.cardSlotsStatus),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Zeitpunkt vorheriger Download', value: s.downloadTime),
                      _InfoRow(label: 'Kartentyp vorheriger Download', value: s.downloadCardType),
                      _InfoRow(label: 'Kartennummer vorheriger Download', value: s.downloadCardNumber),
                      _InfoRow(label: 'Kartengeneration', value: s.downloadCardGeneration),
                      _InfoRow(label: 'Firmenname vorheriger Download', value: s.downloadCompanyName),
                      const SizedBox(height: 16),
                      _CollapsibleSection(
                        title: 'Unternehmenssperren',
                        isEmpty: locks.isEmpty,
                        emptyText: 'Keine Unternehmenssperren vorhanden.',
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Beginn')),
                              DataColumn(label: Text('Ende')),
                              DataColumn(label: Text('Firmenname')),
                              DataColumn(label: Text('Firmenadresse')),
                              DataColumn(label: Text('Kartennummer')),
                            ],
                            rows: locks
                                .map(
                                  (l) => DataRow(
                                    cells: [
                                      DataCell(Text(_display(l.lockIn))),
                                      DataCell(Text(_display(l.lockOut))),
                                      DataCell(Text(_display(l.companyName))),
                                      DataCell(Text(_display(l.companyAddress))),
                                      DataCell(Text(_display(l.cardNumber))),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (outcome.eventsAndFaults.isNotEmpty)
                  ...outcome.eventsAndFaults.map((ef) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ereignisse und Fehler', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            _CollapsibleSection(
                              title: 'Fehler',
                              isEmpty: ef.faults.isEmpty,
                              emptyText: 'Keine Fehler vorhanden.',
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Fehlertyp')),
                                    DataColumn(label: Text('Zweck')),
                                    DataColumn(label: Text('Beginn')),
                                    DataColumn(label: Text('Ende')),
                                    DataColumn(label: Text('Karte Fahrer Beginn')),
                                    DataColumn(label: Text('Karte Fahrer Ende')),
                                    DataColumn(label: Text('Karte Beifahrer Beginn')),
                                    DataColumn(label: Text('Karte Beifahrer Ende')),
                                  ],
                                  rows: ef.faults
                                      .map(
                                        (f) => DataRow(
                                          cells: [
                                            DataCell(Text(_display(f.faultType))),
                                            DataCell(Text(_display(f.purpose))),
                                            DataCell(Text(_display(f.begin))),
                                            DataCell(Text(_display(f.end))),
                                            DataCell(Text(_display(f.driverCardBegin))),
                                            DataCell(Text(_display(f.driverCardEnd))),
                                            DataCell(Text(_display(f.coDriverCardBegin))),
                                            DataCell(Text(_display(f.coDriverCardEnd))),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CollapsibleSection(
                              title: 'Ereignisse',
                              isEmpty: ef.events.isEmpty,
                              emptyText: 'Keine Ereignisse vorhanden.',
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Ereignistyp')),
                                    DataColumn(label: Text('Grund')),
                                    DataColumn(label: Text('Beginn')),
                                    DataColumn(label: Text('Ende')),
                                    DataColumn(label: Text('Anzahl gleichartiger Ereignisse')),
                                    DataColumn(label: Text('Karte Fahrer Beginn')),
                                    DataColumn(label: Text('Karte Fahrer Ende')),
                                  ],
                                  rows: ef.events
                                      .map(
                                        (e) => DataRow(
                                          cells: [
                                            DataCell(Text(_display(e.eventType))),
                                            DataCell(Text(_display(e.purpose))),
                                            DataCell(Text(_display(e.begin))),
                                            DataCell(Text(_display(e.end))),
                                            DataCell(Text(_display(e.similarCount))),
                                            DataCell(Text(_display(e.driverCardBegin))),
                                            DataCell(Text(_display(e.driverCardEnd))),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CollapsibleSection(
                              title: 'Übergeschwindigkeitsereignisse',
                              isEmpty: ef.overSpeed.isEmpty,
                              emptyText: 'Keine Übergeschwindigkeiten vorhanden.',
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Ereignistyp')),
                                    DataColumn(label: Text('Grund')),
                                    DataColumn(label: Text('Beginn')),
                                    DataColumn(label: Text('Ende')),
                                    DataColumn(label: Text('Maximalgeschwindigkeit')),
                                    DataColumn(label: Text('Durchschnittsgeschwindigkeit')),
                                    DataColumn(label: Text('Anzahl gleichartiger Ereignisse')),
                                    DataColumn(label: Text('Karte Fahrer Beginn')),
                                  ],
                                  rows: ef.overSpeed
                                      .map(
                                        (o) => DataRow(
                                          cells: [
                                            DataCell(Text(_display(o.eventType))),
                                            DataCell(Text(_display(o.purpose))),
                                            DataCell(Text(_display(o.begin))),
                                            DataCell(Text(_display(o.end))),
                                            DataCell(Text(_display(o.maxSpeed))),
                                            DataCell(Text(_display(o.avgSpeed))),
                                            DataCell(Text(_display(o.similarCount))),
                                            DataCell(Text(_display(o.driverCardBegin))),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                if (outcome.technicalData.isNotEmpty)
                  ...outcome.technicalData.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Technische Daten', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 10),
                            _InfoRow(label: 'Herstellername', value: t.manufacturerName),
                            _InfoRow(label: 'Herstelleradresse', value: t.manufacturerAddress),
                            _InfoRow(label: 'Teilenummer', value: t.partNumber),
                            _InfoRow(label: 'Seriennummer', value: t.serialNumber),
                            _InfoRow(label: 'Softwareversion', value: t.softwareVersion),
                            _InfoRow(label: 'Software-Installationsdatum', value: t.softwareInstallDate),
                            _InfoRow(label: 'Herstellungsdatum', value: t.manufacturingDate),
                            _InfoRow(label: 'Genehmigungsnummer', value: t.approvalNumber),
                            _InfoRow(label: 'Sensor-Seriennummer', value: t.sensorSerialNumber),
                            _InfoRow(label: 'Sensor-Genehmigungsnummer', value: t.sensorApprovalNumber),
                            _InfoRow(label: 'Sensor Erstkopplung', value: t.sensorPairingDate),
                            const SizedBox(height: 14),
                            _CollapsibleSection(
                              title: 'Kalibrierungsdaten',
                              isEmpty: t.calibrationRows.isEmpty,
                              emptyText: 'Keine Kalibrierungsdaten vorhanden.',
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Kalibrierungsgrund')),
                                    DataColumn(label: Text('Werkstattname')),
                                    DataColumn(label: Text('Werkstattadresse')),
                                    DataColumn(label: Text('Kartentyp')),
                                    DataColumn(label: Text('Kartenausstellungsland')),
                                    DataColumn(label: Text('Kartennummer')),
                                    DataColumn(label: Text('Karte gültig bis')),
                                    DataColumn(label: Text('VIN')),
                                    DataColumn(label: Text('Kennzeichen Land')),
                                    DataColumn(label: Text('Kennzeichen')),
                                    DataColumn(label: Text('Fahrzeugkonstante')),
                                    DataColumn(label: Text('Kontrollgerätkonstante')),
                                    DataColumn(label: Text('Reifenumfang')),
                                    DataColumn(label: Text('Reifengröße')),
                                    DataColumn(label: Text('Erlaubte Höchstgeschwindigkeit')),
                                    DataColumn(label: Text('Alter Kilometerstand')),
                                    DataColumn(label: Text('Neuer Kilometerstand')),
                                    DataColumn(label: Text('Alte Uhrzeit')),
                                    DataColumn(label: Text('Neue Uhrzeit')),
                                    DataColumn(label: Text('Nächste Kalibrierung')),
                                  ],
                                  rows: t.calibrationRows
                                      .map(
                                        (c) => DataRow(
                                          cells: [
                                            DataCell(Text(_display(c.purpose))),
                                            DataCell(Text(_display(c.workshopName))),
                                            DataCell(Text(_display(c.workshopAddress))),
                                            DataCell(Text(_display(c.cardType))),
                                            DataCell(Text(_display(c.cardCountry))),
                                            DataCell(Text(_display(c.cardNumber))),
                                            DataCell(Text(_display(c.cardExpiry))),
                                            DataCell(Text(_display(c.vin))),
                                            DataCell(Text(_display(c.plateCountry))),
                                            DataCell(Text(_display(c.plate))),
                                            DataCell(Text(_display(c.vehicleConstant))),
                                            DataCell(Text(_display(c.equipmentConstant))),
                                            DataCell(Text(_display(c.tyreCircumference))),
                                            DataCell(Text(_display(c.tyreSize))),
                                            DataCell(Text(_display(c.authorisedSpeed))),
                                            DataCell(Text(_display(c.oldOdometer))),
                                            DataCell(Text(_display(c.newOdometer))),
                                            DataCell(Text(_display(c.oldTime))),
                                            DataCell(Text(_display(c.newTime))),
                                            DataCell(Text(_display(c.nextCalibration))),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                ...outcome.driverActivities.map((da) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fahreraktivität', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 10),
                          _InfoRow(label: 'Zeitpunkt (aus JSON)', value: da.dayOriginal),
                          _InfoRow(label: 'Kilometerstand um Mitternacht', value: da.midnightOdometer),
                          const SizedBox(height: 12),
                          _CollapsibleSection(
                            title: 'Kartendaten',
                            isEmpty: da.cardRows.isEmpty,
                            emptyText: 'Keine Kartendaten vorhanden.',
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Vorname')),
                                  DataColumn(label: Text('Nachname')),
                                  DataColumn(label: Text('Kartenslot')),
                                  DataColumn(label: Text('Kartentyp')),
                                  DataColumn(label: Text('Kartenausstellungsland')),
                                  DataColumn(label: Text('Kartennummer')),
                                  DataColumn(label: Text('Kartengültigkeitsende')),
                                  DataColumn(label: Text('Karteneinschubzeit')),
                                  DataColumn(label: Text('Kartenentnahmezeit')),
                                  DataColumn(label: Text('Km bei Einschub')),
                                  DataColumn(label: Text('Km bei Entnahme')),
                                  DataColumn(label: Text('Land vorheriges Fahrzeug')),
                                  DataColumn(label: Text('Kennzeichen vorheriges Fahrzeug')),
                                  DataColumn(label: Text('Kartenentnahme vorheriges Fahrzeug')),
                                ],
                                rows: da.cardRows
                                    .map(
                                      (r) => DataRow(
                                        cells: [
                                          DataCell(Text(_display(r.firstName))),
                                          DataCell(Text(_display(r.lastName))),
                                          DataCell(Text(_display(r.cardSlot))),
                                          DataCell(Text(_display(r.cardType))),
                                          DataCell(Text(_display(r.cardIssuingCountry))),
                                          DataCell(Text(_display(r.cardNumber))),
                                          DataCell(Text(_display(r.cardExpiry))),
                                          DataCell(Text(_display(r.cardInsertion))),
                                          DataCell(Text(_display(r.cardWithdrawal))),
                                          DataCell(Text(_display(r.odoInsertion))),
                                          DataCell(Text(_display(r.odoWithdrawal))),
                                          DataCell(Text(_display(r.prevNation))),
                                          DataCell(Text(_display(r.prevPlate))),
                                          DataCell(Text(_display(r.prevCardWithdrawal))),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _CollapsibleSection(
                            title: 'Tägliche Aktivitäten',
                            isEmpty: da.activityRows.isEmpty,
                            emptyText: 'Keine Aktivitäten gefunden.',
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Zeitpunkt')),
                                  DataColumn(label: Text('Karte gesteckt')),
                                  DataColumn(label: Text('Fahrzeugführung')),
                                  DataColumn(label: Text('Rolle')),
                                  DataColumn(label: Text('Aktivität')),
                                ],
                                rows: da.activityRows
                                    .map(
                                      (a) => DataRow(
                                        cells: [
                                          DataCell(Text(_display(a.time))),
                                          DataCell(Text(_display(a.cardPresent))),
                                          DataCell(Text(_display(a.team))),
                                          DataCell(Text(_display(a.role))),
                                          DataCell(Text(_display(a.activity))),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _CollapsibleSection(
                            title: 'Orte',
                            isEmpty: da.placeRows.isEmpty,
                            emptyText: 'Keine Orte vorhanden.',
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Kartentyp')),
                                  DataColumn(label: Text('Kartenausstellungsland')),
                                  DataColumn(label: Text('Kartennummer')),
                                  DataColumn(label: Text('Uhrzeit')),
                                  DataColumn(label: Text('Land')),
                                  DataColumn(label: Text('Region')),
                                  DataColumn(label: Text('Kilometerstand')),
                                  DataColumn(label: Text('Eingabeart')),
                                  DataColumn(label: Text('GPS Zeitpunkt')),
                                  DataColumn(label: Text('Breitengrad')),
                                  DataColumn(label: Text('Längengrad')),
                                ],
                                rows: da.placeRows
                                    .map(
                                      (p) => DataRow(
                                        cells: [
                                          DataCell(Text(_display(p.cardType))),
                                          DataCell(Text(_display(p.cardCountry))),
                                          DataCell(Text(_display(p.cardNumber))),
                                          DataCell(Text(_display(p.entryTime))),
                                          DataCell(Text(_display(p.country))),
                                          DataCell(Text(_display(p.region))),
                                          DataCell(Text(_display(p.odometer))),
                                          DataCell(Text(_display(p.entryType))),
                                          DataCell(Text(_display(p.gpsTime))),
                                          DataCell(Text(_display(p.lat))),
                                          DataCell(Text(_display(p.lon))),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _CollapsibleSection(
                            title: 'Orte kontinuierliches Fahren',
                            isEmpty: da.gnssRows.isEmpty,
                            emptyText: 'Keine GNSS-Orte vorhanden.',
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Kartentyp')),
                                  DataColumn(label: Text('Kartenausstellungsland')),
                                  DataColumn(label: Text('Kartennummer')),
                                  DataColumn(label: Text('Zeitpunkt')),
                                  DataColumn(label: Text('GPS Zeitpunkt')),
                                  DataColumn(label: Text('Breitengrad')),
                                  DataColumn(label: Text('Längengrad')),
                                ],
                                rows: da.gnssRows
                                    .map(
                                      (g) => DataRow(
                                        cells: [
                                          DataCell(Text(_display(g.cardType))),
                                          DataCell(Text(_display(g.cardCountry))),
                                          DataCell(Text(_display(g.cardNumber))),
                                          DataCell(Text(_display(g.time))),
                                          DataCell(Text(_display(g.gpsTime))),
                                          DataCell(Text(_display(g.lat))),
                                          DataCell(Text(_display(g.lon))),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _CollapsibleSection(
                            title: 'Ladevorgänge',
                            isEmpty: da.loadRows.isEmpty,
                            emptyText: 'Keine Ladevorgänge vorhanden.',
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Kartentyp')),
                                  DataColumn(label: Text('Kartenausstellungsland')),
                                  DataColumn(label: Text('Kartennummer')),
                                  DataColumn(label: Text('Zeitpunkt')),
                                  DataColumn(label: Text('Arbeitstyp')),
                                  DataColumn(label: Text('GPS Zeitpunkt')),
                                  DataColumn(label: Text('Breitengrad')),
                                  DataColumn(label: Text('Längengrad')),
                                  DataColumn(label: Text('Kilometerstand')),
                                ],
                                rows: da.loadRows
                                    .map(
                                      (l) => DataRow(
                                        cells: [
                                          DataCell(Text(_display(l.cardType))),
                                          DataCell(Text(_display(l.cardCountry))),
                                          DataCell(Text(_display(l.cardNumber))),
                                          DataCell(Text(_display(l.time))),
                                          DataCell(Text(_display(l.operationType))),
                                          DataCell(Text(_display(l.gpsTime))),
                                          DataCell(Text(_display(l.lat))),
                                          DataCell(Text(_display(l.lon))),
                                          DataCell(Text(_display(l.odometer))),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ParserTestOutcome {
  const _ParserTestOutcome({
    required this.summary,
    required this.locks,
    required this.driverActivities,
    required this.technicalData,
    required this.eventsAndFaults,
  });

  final _ParserSummary summary;
  final List<_CompanyLock> locks;
  final List<_DriverActivity> driverActivities;
  final List<_TechnicalData> technicalData;
  final List<_EventsAndFaults> eventsAndFaults;
}

class _ParserSummary {
  const _ParserSummary({
    this.vin,
    this.plate,
    this.currentTime,
    this.periodStart,
    this.periodEnd,
    this.cardSlotsStatus,
    this.downloadTime,
    this.downloadCardType,
    this.downloadCardNumber,
    this.downloadCardGeneration,
    this.downloadCompanyName,
  });

  final String? vin;
  final String? plate;
  final String? currentTime;
  final String? periodStart;
  final String? periodEnd;
  final String? cardSlotsStatus;
  final String? downloadTime;
  final String? downloadCardType;
  final String? downloadCardNumber;
  final String? downloadCardGeneration;
  final String? downloadCompanyName;

  factory _ParserSummary.fromMap(Map<String, dynamic> map) {
    return _ParserSummary(
      vin: map['vin'] as String?,
      plate: map['plate'] as String?,
      currentTime: map['currentTime'] as String?,
      periodStart: map['periodStart'] as String?,
      periodEnd: map['periodEnd'] as String?,
      cardSlotsStatus: map['cardSlotsStatus'] as String?,
      downloadTime: map['downloadTime'] as String?,
      downloadCardType: map['downloadCardType'] as String?,
      downloadCardNumber: map['downloadCardNumber'] as String?,
      downloadCardGeneration: map['downloadCardGeneration'] as String?,
      downloadCompanyName: map['downloadCompanyName'] as String?,
    );
  }
}

List<EventDayBundle> _buildEventBundles(List<_EventsAndFaults> list) {
  final buckets = <int, EventBundle>{};

  void add(DateTime? dt, EventBundle bundle) {
    if (dt == null) return;
    final date = DateTime(dt.year, dt.month, dt.day);
    final key = calendarEventsStore.keyFromDate(date);
    final existing = buckets[key];
    buckets[key] = existing != null ? existing.merge(bundle) : bundle;
  }

  for (final item in list) {
    for (final f in item.faults) {
      add(_parseDateLocal(f.begin ?? f.end), EventBundle(faults: [
        FaultRecord(
          faultType: f.faultType,
          purpose: f.purpose,
          begin: f.begin,
          end: f.end,
          driverBegin: f.driverCardBegin,
          driverEnd: f.driverCardEnd,
          coDriverBegin: f.coDriverCardBegin,
          coDriverEnd: f.coDriverCardEnd,
        )
      ]));
    }
    for (final e in item.events) {
      add(_parseDateLocal(e.begin ?? e.end), EventBundle(events: [
        EventRecord(
          eventType: e.eventType,
          purpose: e.purpose,
          begin: e.begin,
          end: e.end,
          similarCount: e.similarCount,
          driverBegin: e.driverCardBegin,
          driverEnd: e.driverCardEnd,
        )
      ]));
    }
    for (final o in item.overSpeed) {
      add(_parseDateLocal(o.begin ?? o.end), EventBundle(overSpeeds: [
        OverSpeedRecord(
          eventType: o.eventType,
          purpose: o.purpose,
          begin: o.begin,
          end: o.end,
          maxSpeed: o.maxSpeed,
          avgSpeed: o.avgSpeed,
          similarCount: o.similarCount,
          driverBegin: o.driverCardBegin,
        )
      ]));
    }
  }

  return buckets.entries
      .map((e) => EventDayBundle(date: DateTime.fromMillisecondsSinceEpoch(e.key), bundle: e.value))
      .toList();
}

DateTime? _parseDateLocal(String? v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v).toUtc();
  } catch (_) {
    return null;
  }
}

class _DriverActivity {
  const _DriverActivity({
    this.dayOriginal,
    this.midnightOdometer,
    this.cardRows = const [],
    this.activityRows = const [],
    this.placeRows = const [],
    this.gnssRows = const [],
    this.loadRows = const [],
  });

  final String? dayOriginal;
  final String? midnightOdometer;
  final List<_CardIwRow> cardRows;
  final List<_ActivityRow> activityRows;
  final List<_PlaceRow> placeRows;
  final List<_GnssRow> gnssRows;
  final List<_LoadRow> loadRows;

  factory _DriverActivity.fromMap(Map<String, dynamic> map) {
    return _DriverActivity(
      dayOriginal: map['dayOriginal'] as String?,
      midnightOdometer: map['midnightOdometer'] as String?,
      cardRows: (map['cardRows'] as List<dynamic>? ?? [])
          .map((e) => _CardIwRow.fromMap(e as Map<String, dynamic>))
          .toList(),
      activityRows: (map['activityRows'] as List<dynamic>? ?? [])
          .map((e) => _ActivityRow.fromMap(e as Map<String, dynamic>))
          .toList(),
      placeRows: (map['placeRows'] as List<dynamic>? ?? [])
          .map((e) => _PlaceRow.fromMap(e as Map<String, dynamic>))
          .toList(),
      gnssRows: (map['gnssRows'] as List<dynamic>? ?? [])
          .map((e) => _GnssRow.fromMap(e as Map<String, dynamic>))
          .toList(),
      loadRows: (map['loadRows'] as List<dynamic>? ?? [])
          .map((e) => _LoadRow.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _CardIwRow {
  const _CardIwRow({
    this.firstName,
    this.lastName,
    this.cardSlot,
    this.cardType,
    this.cardIssuingCountry,
    this.cardNumber,
    this.cardExpiry,
    this.cardInsertion,
    this.cardWithdrawal,
    this.odoInsertion,
    this.odoWithdrawal,
    this.prevNation,
    this.prevPlate,
    this.prevCardWithdrawal,
  });

  final String? firstName;
  final String? lastName;
  final String? cardSlot;
  final String? cardType;
  final String? cardIssuingCountry;
  final String? cardNumber;
  final String? cardExpiry;
  final String? cardInsertion;
  final String? cardWithdrawal;
  final String? odoInsertion;
  final String? odoWithdrawal;
  final String? prevNation;
  final String? prevPlate;
  final String? prevCardWithdrawal;

  factory _CardIwRow.fromMap(Map<String, dynamic> map) {
    return _CardIwRow(
      firstName: map['firstName'] as String?,
      lastName: map['lastName'] as String?,
      cardSlot: map['cardSlot'] as String?,
      cardType: map['cardType'] as String?,
      cardIssuingCountry: map['cardIssuingCountry'] as String?,
      cardNumber: map['cardNumber'] as String?,
      cardExpiry: map['cardExpiry'] as String?,
      cardInsertion: map['cardInsertion'] as String?,
      cardWithdrawal: map['cardWithdrawal'] as String?,
      odoInsertion: map['odoInsertion'] as String?,
      odoWithdrawal: map['odoWithdrawal'] as String?,
      prevNation: map['prevNation'] as String?,
      prevPlate: map['prevPlate'] as String?,
      prevCardWithdrawal: map['prevCardWithdrawal'] as String?,
    );
  }
}

class _ActivityRow {
  const _ActivityRow({
    this.time,
    this.cardPresent,
    this.team,
    this.role,
    this.activity,
  });

  final String? time;
  final String? cardPresent;
  final String? team;
  final String? role;
  final String? activity;

  factory _ActivityRow.fromMap(Map<String, dynamic> map) {
    return _ActivityRow(
      time: map['time'] as String?,
      cardPresent: map['cardPresent'] as String?,
      team: map['team'] as String?,
      role: map['role'] as String?,
      activity: map['activity'] as String?,
    );
  }
}

class _PlaceRow {
  const _PlaceRow({
    this.cardType,
    this.cardCountry,
    this.cardNumber,
    this.entryTime,
    this.country,
    this.region,
    this.odometer,
    this.entryType,
    this.gpsTime,
    this.lat,
    this.lon,
  });

  final String? cardType;
  final String? cardCountry;
  final String? cardNumber;
  final String? entryTime;
  final String? country;
  final String? region;
  final String? odometer;
  final String? entryType;
  final String? gpsTime;
  final String? lat;
  final String? lon;

  factory _PlaceRow.fromMap(Map<String, dynamic> map) {
    return _PlaceRow(
      cardType: map['cardType'] as String?,
      cardCountry: map['cardCountry'] as String?,
      cardNumber: map['cardNumber'] as String?,
      entryTime: map['entryTime'] as String?,
      country: map['country'] as String?,
      region: map['region'] as String?,
      odometer: map['odometer'] as String?,
      entryType: map['entryType'] as String?,
      gpsTime: map['gpsTime'] as String?,
      lat: map['lat'] as String?,
      lon: map['lon'] as String?,
    );
  }
}

class _GnssRow {
  const _GnssRow({
    this.cardType,
    this.cardCountry,
    this.cardNumber,
    this.time,
    this.gpsTime,
    this.lat,
    this.lon,
  });

  final String? cardType;
  final String? cardCountry;
  final String? cardNumber;
  final String? time;
  final String? gpsTime;
  final String? lat;
  final String? lon;

  factory _GnssRow.fromMap(Map<String, dynamic> map) {
    return _GnssRow(
      cardType: map['cardType'] as String?,
      cardCountry: map['cardCountry'] as String?,
      cardNumber: map['cardNumber'] as String?,
      time: map['time'] as String?,
      gpsTime: map['gpsTime'] as String?,
      lat: map['lat'] as String?,
      lon: map['lon'] as String?,
    );
  }
}

class _LoadRow {
  const _LoadRow({
    this.cardType,
    this.cardCountry,
    this.cardNumber,
    this.time,
    this.operationType,
    this.gpsTime,
    this.lat,
    this.lon,
    this.odometer,
  });

  final String? cardType;
  final String? cardCountry;
  final String? cardNumber;
  final String? time;
  final String? operationType;
  final String? gpsTime;
  final String? lat;
  final String? lon;
  final String? odometer;

  factory _LoadRow.fromMap(Map<String, dynamic> map) {
    return _LoadRow(
      cardType: map['cardType'] as String?,
      cardCountry: map['cardCountry'] as String?,
      cardNumber: map['cardNumber'] as String?,
      time: map['time'] as String?,
      operationType: map['operationType'] as String?,
      gpsTime: map['gpsTime'] as String?,
      lat: map['lat'] as String?,
      lon: map['lon'] as String?,
      odometer: map['odometer'] as String?,
    );
  }
}

class _CompanyLock {
  const _CompanyLock({
    this.lockIn,
    this.lockOut,
    this.companyName,
    this.companyAddress,
    this.cardNumber,
  });

  final String? lockIn;
  final String? lockOut;
  final String? companyName;
  final String? companyAddress;
  final String? cardNumber;

  factory _CompanyLock.fromMap(Map<String, dynamic> map) {
    String? cardNumber;
    final cardGen = map['company_card_number_and_generation'];
    if (cardGen is Map<String, dynamic>) {
      final full = cardGen['full_card_number'];
      if (full is Map<String, dynamic>) {
        cardNumber = full['card_number']?.toString();
      }
    }
    return _CompanyLock(
      lockIn: map['lock_in_time']?.toString(),
      lockOut: map['lock_out_time']?.toString(),
      companyName: map['company_name']?.toString(),
      companyAddress: map['company_address']?.toString(),
      cardNumber: cardNumber,
    );
  }
}

class _TechnicalData {
  const _TechnicalData({
    this.manufacturerName,
    this.manufacturerAddress,
    this.partNumber,
    this.serialNumber,
    this.softwareVersion,
    this.softwareInstallDate,
    this.manufacturingDate,
    this.approvalNumber,
    this.sensorSerialNumber,
    this.sensorApprovalNumber,
    this.sensorPairingDate,
    this.calibrationRows = const [],
  });

  final String? manufacturerName;
  final String? manufacturerAddress;
  final String? partNumber;
  final String? serialNumber;
  final String? softwareVersion;
  final String? softwareInstallDate;
  final String? manufacturingDate;
  final String? approvalNumber;
  final String? sensorSerialNumber;
  final String? sensorApprovalNumber;
  final String? sensorPairingDate;
  final List<_CalibrationRow> calibrationRows;

  factory _TechnicalData.fromMap(Map<String, dynamic> map) {
    return _TechnicalData(
      manufacturerName: map['manufacturerName'] as String?,
      manufacturerAddress: map['manufacturerAddress'] as String?,
      partNumber: map['partNumber'] as String?,
      serialNumber: map['serialNumber'] as String?,
      softwareVersion: map['softwareVersion'] as String?,
      softwareInstallDate: map['softwareInstallDate'] as String?,
      manufacturingDate: map['manufacturingDate'] as String?,
      approvalNumber: map['approvalNumber'] as String?,
      sensorSerialNumber: map['sensorSerialNumber'] as String?,
      sensorApprovalNumber: map['sensorApprovalNumber'] as String?,
      sensorPairingDate: map['sensorPairingDate'] as String?,
      calibrationRows: (map['calibrationRows'] as List<dynamic>? ?? [])
          .map((e) => _CalibrationRow.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _EventsAndFaults {
  const _EventsAndFaults({
    this.faults = const [],
    this.events = const [],
    this.overSpeed = const [],
  });

  final List<_FaultRow> faults;
  final List<_EventRow> events;
  final List<_OverSpeedRow> overSpeed;

  factory _EventsAndFaults.fromMap(Map<String, dynamic> map) {
    return _EventsAndFaults(
      faults: (map['faults'] as List<dynamic>? ?? [])
          .map((e) => _FaultRow.fromMap(e as Map<String, dynamic>))
          .toList(),
      events: (map['events'] as List<dynamic>? ?? [])
          .map((e) => _EventRow.fromMap(e as Map<String, dynamic>))
          .toList(),
      overSpeed: (map['overSpeed'] as List<dynamic>? ?? [])
          .map((e) => _OverSpeedRow.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _FaultRow {
  const _FaultRow({
    this.faultType,
    this.purpose,
    this.begin,
    this.end,
    this.driverCardBegin,
    this.driverCardEnd,
    this.coDriverCardBegin,
    this.coDriverCardEnd,
  });

  final String? faultType;
  final String? purpose;
  final String? begin;
  final String? end;
  final String? driverCardBegin;
  final String? driverCardEnd;
  final String? coDriverCardBegin;
  final String? coDriverCardEnd;

  factory _FaultRow.fromMap(Map<String, dynamic> map) {
    return _FaultRow(
      faultType: map['faultType'] as String?,
      purpose: map['purpose'] as String?,
      begin: map['begin'] as String?,
      end: map['end'] as String?,
      driverCardBegin: map['driverCardBegin'] as String?,
      driverCardEnd: map['driverCardEnd'] as String?,
      coDriverCardBegin: map['coDriverCardBegin'] as String?,
      coDriverCardEnd: map['coDriverCardEnd'] as String?,
    );
  }
}

class _EventRow {
  const _EventRow({
    this.eventType,
    this.purpose,
    this.begin,
    this.end,
    this.similarCount,
    this.driverCardBegin,
    this.driverCardEnd,
  });

  final String? eventType;
  final String? purpose;
  final String? begin;
  final String? end;
  final String? similarCount;
  final String? driverCardBegin;
  final String? driverCardEnd;

  factory _EventRow.fromMap(Map<String, dynamic> map) {
    return _EventRow(
      eventType: map['eventType'] as String?,
      purpose: map['purpose'] as String?,
      begin: map['begin'] as String?,
      end: map['end'] as String?,
      similarCount: map['similarCount'] as String?,
      driverCardBegin: map['driverCardBegin'] as String?,
      driverCardEnd: map['driverCardEnd'] as String?,
    );
  }
}

class _OverSpeedRow {
  const _OverSpeedRow({
    this.eventType,
    this.purpose,
    this.begin,
    this.end,
    this.maxSpeed,
    this.avgSpeed,
    this.similarCount,
    this.driverCardBegin,
  });

  final String? eventType;
  final String? purpose;
  final String? begin;
  final String? end;
  final String? maxSpeed;
  final String? avgSpeed;
  final String? similarCount;
  final String? driverCardBegin;

  factory _OverSpeedRow.fromMap(Map<String, dynamic> map) {
    return _OverSpeedRow(
      eventType: map['eventType'] as String?,
      purpose: map['purpose'] as String?,
      begin: map['begin'] as String?,
      end: map['end'] as String?,
      maxSpeed: map['maxSpeed'] as String?,
      avgSpeed: map['avgSpeed'] as String?,
      similarCount: map['similarCount'] as String?,
      driverCardBegin: map['driverCardBegin'] as String?,
    );
  }
}
class _CalibrationRow {
  const _CalibrationRow({
    this.purpose,
    this.workshopName,
    this.workshopAddress,
    this.cardType,
    this.cardCountry,
    this.cardNumber,
    this.cardExpiry,
    this.vin,
    this.plateCountry,
    this.plate,
    this.vehicleConstant,
    this.equipmentConstant,
    this.tyreCircumference,
    this.tyreSize,
    this.authorisedSpeed,
    this.oldOdometer,
    this.newOdometer,
    this.oldTime,
    this.newTime,
    this.nextCalibration,
  });

  final String? purpose;
  final String? workshopName;
  final String? workshopAddress;
  final String? cardType;
  final String? cardCountry;
  final String? cardNumber;
  final String? cardExpiry;
  final String? vin;
  final String? plateCountry;
  final String? plate;
  final String? vehicleConstant;
  final String? equipmentConstant;
  final String? tyreCircumference;
  final String? tyreSize;
  final String? authorisedSpeed;
  final String? oldOdometer;
  final String? newOdometer;
  final String? oldTime;
  final String? newTime;
  final String? nextCalibration;

  factory _CalibrationRow.fromMap(Map<String, dynamic> map) {
    return _CalibrationRow(
      purpose: map['purpose'] as String?,
      workshopName: map['workshopName'] as String?,
      workshopAddress: map['workshopAddress'] as String?,
      cardType: map['cardType'] as String?,
      cardCountry: map['cardCountry'] as String?,
      cardNumber: map['cardNumber'] as String?,
      cardExpiry: map['cardExpiry'] as String?,
      vin: map['vin'] as String?,
      plateCountry: map['plateCountry'] as String?,
      plate: map['plate'] as String?,
      vehicleConstant: map['vehicleConstant'] as String?,
      equipmentConstant: map['equipmentConstant'] as String?,
      tyreCircumference: map['tyreCircumference'] as String?,
      tyreSize: map['tyreSize'] as String?,
      authorisedSpeed: map['authorisedSpeed'] as String?,
      oldOdometer: map['oldOdometer'] as String?,
      newOdometer: map['newOdometer'] as String?,
      oldTime: map['oldTime'] as String?,
      newTime: map['newTime'] as String?,
      nextCalibration: map['nextCalibration'] as String?,
    );
  }
}
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 3,
            child: Text(value?.isNotEmpty == true ? value! : '–', style: text.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Läuft im Hintergrund-Isolate, damit große JSONs das UI nicht blockieren.
Map<String, dynamic> _parseJsonAndSummary(String raw) {
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    decoded = null;
  }

  final summary = _extractSummaryMap(decoded);
  final locks = _extractLocks(decoded);
  final driverActivities = _extractDriverActivities(decoded);
  final technicalData = _extractTechnicalData(decoded);
  final eventsAndFaults = _extractEventsAndFaults(decoded);
  return {
    'summary': summary,
    'locks': locks,
    'driverActivities': driverActivities,
    'technicalData': technicalData,
    'eventsAndFaults': eventsAndFaults,
  };
}

Map<String, String?> _extractSummaryMap(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) return {};
  final overview = decoded['vu_overview_2_v2'];
  if (overview is! Map<String, dynamic>) return {};

  final summary = <String, String?>{};

  summary['vin'] =
      _firstStringFromRecords(overview['vehicle_identification_number_record_array']);

  // Kennzeichen
  final plateRecs = _recordsList(overview['vehicle_registration_identification_record_array']);
  if (plateRecs != null && plateRecs.isNotEmpty) {
    final first = plateRecs.first;
    if (first is Map<String, dynamic>) {
      summary['plate'] = first['vehicle_registration_number']?.toString();
    } else if (first != null) {
      summary['plate'] = first.toString();
    }
  }

  summary['currentTime'] = _firstStringFromRecords(overview['current_date_time_record_array']);

  // Downloadable period
  final periodRecs = _recordsList(overview['vu_downloadable_period_record_array']);
  if (periodRecs != null && periodRecs.isNotEmpty) {
    final p = periodRecs.first;
    if (p is Map<String, dynamic>) {
      summary['periodStart'] = p['min_downloadable_time']?.toString();
      summary['periodEnd'] = p['max_downloadable_time']?.toString();
    }
  }

  summary['cardSlotsStatus'] = _stringifyRecord(overview['card_slots_status_record_array']);

  // Download activity
  final downloadRecs = _recordsList(overview['vu_download_activity_data_record_array']);
  if (downloadRecs != null && downloadRecs.isNotEmpty) {
    final rec = downloadRecs.first;
    if (rec is Map<String, dynamic>) {
      summary['downloadTime'] = rec['downloading_time']?.toString();
      final fcg = rec['full_card_number_and_generation'];
      if (fcg is Map<String, dynamic>) {
        summary['downloadCardGeneration'] = fcg['generation']?.toString();
        final full = fcg['full_card_number'];
        if (full is Map<String, dynamic>) {
          summary['downloadCardType'] = full['card_type']?.toString();
          summary['downloadCardNumber'] = full['card_number']?.toString();
        }
      }
      summary['downloadCompanyName'] = rec['company_or_workshop_name']?.toString();
    }
  }

  return summary;
}

List<Map<String, dynamic>> _extractLocks(dynamic decoded) {
  if (decoded is! Map<String, dynamic>) return const [];
  final overview = decoded['vu_overview_2_v2'];
  if (overview is! Map<String, dynamic>) return const [];
  final locksArray = overview['vu_company_locks_record_array'];
  final recs = _recordsList(locksArray);
  if (recs == null) return const [];
  return recs
      .whereType<Map<String, dynamic>>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

List<Map<String, dynamic>> _extractPlaces(Map<String, dynamic> first) {
  final recs = _recordsList(first['vu_place_daily_work_period_record_array']);
  if (recs == null) return const [];
  final rows = <Map<String, dynamic>>[];
  for (final rec in recs.whereType<Map<String, dynamic>>()) {
    final card = _fullCardFrom(rec['full_card_number_and_generation']);
    final placeAuth = rec['place_auth_record'] as Map<String, dynamic>?;
    final gnss = placeAuth?['entry_gnss_place_auth_record'] as Map<String, dynamic>?;
    final geo = gnss?['geo_coordinates'] as Map<String, dynamic>?;
    rows.add({
      'cardType': _mapCardType(card['card_type']),
      'cardCountry': _mapCountry(card['card_issuing_member_state']),
      'cardNumber': card['card_number']?.toString(),
      'entryTime': placeAuth?['entry_time']?.toString(),
      'country': _mapCountry(placeAuth?['daily_work_period_country']),
      'region': placeAuth?['daily_work_period_region']?.toString(),
      'odometer': placeAuth?['vehicle_odometer_value']?.toString(),
      'entryType': _mapEntryType(placeAuth?['entry_type_daily_work_period']),
      'gpsTime': gnss?['time_stamp']?.toString(),
      'lat': geo?['latitude']?.toString(),
      'lon': geo?['longitude']?.toString(),
    });
  }
  return rows;
}

List<Map<String, dynamic>> _extractGnss(Map<String, dynamic> first) {
  final recs = _recordsList(first['vu_gnss_ad_record_array']);
  if (recs == null) return const [];
  final rows = <Map<String, dynamic>>[];
  for (final rec in recs.whereType<Map<String, dynamic>>()) {
    final gnss = rec['gnss_place_auth_record'] as Map<String, dynamic>?;
    final geo = gnss?['geo_coordinates'] as Map<String, dynamic>?;
    final card = _fullCardFrom(rec['card_number_and_gen_driver_slot']);
    rows.add({
      'cardType': _mapCardType(card['card_type']),
      'cardCountry': _mapCountry(card['card_issuing_member_state']),
      'cardNumber': card['card_number']?.toString(),
      'time': rec['time_stamp']?.toString(),
      'gpsTime': gnss?['time_stamp']?.toString(),
      'lat': geo?['latitude']?.toString(),
      'lon': geo?['longitude']?.toString(),
    });
  }
  return rows;
}

List<Map<String, dynamic>> _extractLoads(Map<String, dynamic> first) {
  final recs = _recordsList(first['vu_load_unload_record_array']);
  if (recs == null) return const [];
  final rows = <Map<String, dynamic>>[];
  for (final rec in recs.whereType<Map<String, dynamic>>()) {
    final gnss = rec['gnss_place_auth_record'] as Map<String, dynamic>?;
    final geo = gnss?['geo_coordinates'] as Map<String, dynamic>?;
    final card = _fullCardFrom(rec['card_number_and_gen_driver_slot']);
    rows.add({
      'cardType': _mapCardType(card['card_type']),
      'cardCountry': _mapCountry(card['card_issuing_member_state']),
      'cardNumber': card['card_number']?.toString(),
      'time': rec['time_stamp']?.toString(),
      'operationType': rec['operation_type']?.toString(),
      'gpsTime': gnss?['time_stamp']?.toString(),
      'lat': geo?['latitude']?.toString(),
      'lon': geo?['longitude']?.toString(),
      'odometer': rec['vehicle_odometer_value']?.toString(),
    });
  }
  return rows;
}

List<Map<String, dynamic>> _extractTechnicalData(dynamic decoded) {
  final result = <Map<String, dynamic>>[];
  if (decoded is! Map<String, dynamic>) return result;
  final tech = decoded['vu_technical_data_2_v2'];
  final list = tech is List
      ? tech
      : tech is Map<String, dynamic>
          ? [tech]
          : const [];
  for (final item in list) {
    if (item is! Map<String, dynamic>) continue;
    final identRecs = _recordsList(item['vu_identification_record_array']);
    final ident = (identRecs != null && identRecs.isNotEmpty && identRecs.first is Map<String, dynamic>)
        ? identRecs.first as Map<String, dynamic>
        : const <String, dynamic>{};

    final sensorRecords = _recordsList(item['vu_sensor_paired_record_array']);
    final sensor = (sensorRecords != null && sensorRecords.isNotEmpty && sensorRecords.first is Map<String, dynamic>)
        ? sensorRecords.first as Map<String, dynamic>
        : const <String, dynamic>{};

    final calibRecs = _recordsList(item['vu_calibration_record_array']);

    result.add({
      'manufacturerName': _decodeAscii(ident['vu_manufacturer_name']),
      'manufacturerAddress': _decodeAscii(ident['vu_manufacturer_address']),
      'partNumber': _decodeAscii(ident['vu_part_number']),
      'serialNumber': _decodeAscii(ident['vu_serial_number'] is Map ? (ident['vu_serial_number'] as Map)['serial_number'] : ident['vu_serial_number']),
      'softwareVersion': _decodeAscii(ident['vu_software_identification']?['vu_software_version']),
      'softwareInstallDate': ident['vu_software_identification']?['vu_soft_installation_date']?.toString(),
      'manufacturingDate': ident['vu_manufacturing_date']?.toString(),
      'approvalNumber': _decodeAscii(ident['vu_approval_number']),
      'sensorSerialNumber': _decodeAscii(sensor['sensor_serial_number'] is Map ? (sensor['sensor_serial_number'] as Map)['serial_number'] : sensor['sensor_serial_number']),
      'sensorApprovalNumber': _decodeAscii(sensor['sensor_approval_number']),
      'sensorPairingDate': sensor['sensor_pairing_date']?.toString(),
      'calibrationRows': (calibRecs ?? [])
          .whereType<Map<String, dynamic>>()
          .map(_mapCalibrationRecord)
          .toList(),
    });
  }
  return result;
}

List<Map<String, dynamic>> _extractDriverActivities(dynamic decoded) {
  final result = <Map<String, dynamic>>[];
  if (decoded is! Map<String, dynamic>) return result;
  final activities = decoded['vu_activities_2_v2'];
  final list = activities is List
      ? activities
      : activities is Map<String, dynamic>
          ? [activities]
          : const [];
  for (final item in list) {
    if (item is! Map<String, dynamic>) continue;

    final baseDateStr = _firstStringFromRecords(item['date_of_day_downloaded_record_array']);
    final baseDate = _parseDateLocal(baseDateStr);
    final baseMidnight = baseDate != null ? DateTime.utc(baseDate.year, baseDate.month, baseDate.day) : null;

    final cardRows = <Map<String, dynamic>>[];
    final cardRecs = _recordsList(item['vu_card_iw_record_array']);
    if (cardRecs != null) {
      for (final rec in cardRecs) {
        if (rec is! Map<String, dynamic>) continue;
        final cardInfo = rec['full_card_number_and_generation'];
        Map<String, dynamic>? fullCard;
        if (cardInfo is Map<String, dynamic>) {
          final full = cardInfo['full_card_number'];
          if (full is Map<String, dynamic>) {
            fullCard = full;
          }
        }
        final prevVehicle = rec['previous_vehicle_info'] as Map<String, dynamic>?;
        final prevReg = prevVehicle?['vehicle_registration_identification'] as Map<String, dynamic>?;

        cardRows.add({
          'firstName': (rec['card_holder_name'] as Map<String, dynamic>?)?['holder_first_names']?.toString(),
          'lastName': (rec['card_holder_name'] as Map<String, dynamic>?)?['holder_surname']?.toString(),
          'cardSlot': rec['card_slot_number']?.toString(),
          'cardType': _mapCardType(fullCard?['card_type']),
          'cardIssuingCountry': fullCard?['card_issuing_member_state']?.toString(),
          'cardNumber': fullCard?['card_number']?.toString(),
          'cardExpiry': rec['card_expiry_date']?.toString(),
          'cardInsertion': rec['card_insertion_time']?.toString(),
          'cardWithdrawal': rec['card_withdrawal_time']?.toString(),
          'odoInsertion': rec['vehicle_odometer_value_at_insertion']?.toString(),
          'odoWithdrawal': rec['vehicle_odometer_value_at_withdrawal']?.toString(),
          'prevNation': prevReg?['vehicle_registration_nation']?.toString(),
          'prevPlate': prevReg?['vehicle_registration_number']?.toString(),
          'prevCardWithdrawal': prevVehicle?['card_withdrawal_time']?.toString(),
        });
      }
    }

    final activityRows = <Map<String, dynamic>>[];
    final activityRecs = _recordsList(item['vu_activity_daily_record_array']);
    if (activityRecs != null) {
      for (final rec in activityRecs.whereType<Map<String, dynamic>>()) {
        final minutes = rec['minutes'] is num ? (rec['minutes'] as num).toInt() : null;
        final time = (baseMidnight != null && minutes != null)
            ? _formatDateTime(baseMidnight.add(Duration(minutes: minutes)))
            : null;

        activityRows.add({
          'time': time ?? baseDateStr,
          'cardPresent': _mapCardPresent(rec['card_present']),
          'team': _mapTeam(rec['team']),
          'role': _mapRole(rec['driver']),
          'activity': _mapWorkType(rec['work_type']),
        });
      }
    }

    result.add({
      'dayOriginal': baseDateStr,
      'midnightOdometer': _firstStringFromRecords(item['odometer_value_midnight_record_array']),
      'cardRows': cardRows,
      'activityRows': activityRows,
      'placeRows': _extractPlaces(item),
      'gnssRows': _extractGnss(item),
      'loadRows': _extractLoads(item),
    });
  }
  return result;
}

List<Map<String, dynamic>> _extractEventsAndFaults(dynamic decoded) {
  final result = <Map<String, dynamic>>[];
  if (decoded is! Map<String, dynamic>) return result;
  final efa = decoded['vu_events_and_faults_2_v2'];
  final list = efa is List
      ? efa
      : efa is Map<String, dynamic>
          ? [efa]
          : const [];
  for (final item in list) {
    if (item is! Map<String, dynamic>) continue;

    final faults = <Map<String, dynamic>>[];
    final faultRecs = _recordsList(item['vu_fault_record_array']);
    if (faultRecs != null) {
      for (final rec in faultRecs.whereType<Map<String, dynamic>>()) {
        faults.add({
          'faultType': rec['fault_type']?.toString(),
          'purpose': rec['fault_record_purpose']?.toString(),
          'begin': rec['fault_begin_time']?.toString(),
          'end': rec['fault_end_time']?.toString(),
          'driverCardBegin': _cardStringFrom(rec['card_number_and_gen_driver_slot_begin']),
          'driverCardEnd': _cardStringFrom(rec['card_number_and_gen_driver_slot_end']),
          'coDriverCardBegin': _cardStringFrom(rec['card_number_and_gen_codriver_slot_begin']),
          'coDriverCardEnd': _cardStringFrom(rec['card_number_and_gen_codriver_slot_end']),
        });
      }
    }

    final events = <Map<String, dynamic>>[];
    final eventRecs = _recordsList(item['vu_event_record_array']);
    if (eventRecs != null) {
      for (final rec in eventRecs.whereType<Map<String, dynamic>>()) {
        events.add({
          'eventType': _mapEventType(rec['event_type']),
          'purpose': rec['event_record_purpose']?.toString(),
          'begin': rec['event_begin_time']?.toString(),
          'end': rec['event_end_time']?.toString(),
          'similarCount': rec['similar_events_number']?.toString(),
          'driverCardBegin': _cardStringFrom(rec['card_number_and_gen_codriver_slot_begin']),
          'driverCardEnd': _cardStringFrom(rec['card_number_and_gen_driver_slot_end']),
        });
      }
    }

    final overspeed = <Map<String, dynamic>>[];
    final overRecs = _recordsList(item['vu_over_speeding_event_record_array']);
    if (overRecs != null) {
      for (final rec in overRecs.whereType<Map<String, dynamic>>()) {
        overspeed.add({
          'eventType': _mapOverSpeedEventType(rec['event_type']),
          'purpose': rec['event_record_purpose']?.toString(),
          'begin': rec['event_begin_time']?.toString(),
          'end': rec['event_end_time']?.toString(),
          'maxSpeed': rec['max_speed_value']?.toString(),
          'avgSpeed': rec['average_speed_value']?.toString(),
          'similarCount': rec['similar_events_number']?.toString(),
          'driverCardBegin': _cardStringFrom(rec['card_number_and_gen_driver_slot_begin']),
        });
      }
    }

    result.add({
      'faults': faults,
      'events': events,
      'overSpeed': overspeed,
    });
  }
  return result;
}

List<dynamic>? _recordsList(dynamic recordArray) {
  if (recordArray is Map<String, dynamic>) {
    final recs = recordArray['records'];
    if (recs is List) return recs;
    if (recs != null) return [recs];
  } else if (recordArray is List) {
    return recordArray;
  } else if (recordArray != null) {
    return [recordArray];
  }
  return null;
}

String? _firstStringFromRecords(dynamic recordArray) {
  final recs = _recordsList(recordArray);
  if (recs == null || recs.isEmpty) return null;
  final first = recs.first;
  if (first == null) return null;
  return first.toString();
}

String? _stringifyRecord(dynamic recordArray) {
  final recs = _recordsList(recordArray);
  if (recs == null || recs.isEmpty) return null;
  final first = recs.first;
  if (first == null) return null;
  return first.toString();
}

DateTime? _parseDateUtc(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value).toUtc();
  } catch (_) {
    return null;
  }
}

String _formatDateTime(DateTime dt) {
  // Keep it simple, ISO-like without 'T' for readability.
  final two = (int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

String? _mapCardType(dynamic value) {
  if (value is! num) return value?.toString();
  if (value == 1) return 'Fahrerkarte';
  return 'Typ ${value.toString()}';
}

String? _mapCardPresent(dynamic value) {
  if (value is bool) return value ? 'Nein' : 'Ja';
  return value?.toString();
}

String? _mapTeam(dynamic value) {
  if (value is bool) return value ? 'Team' : 'Einmannbetrieb';
  return value?.toString();
}

String? _mapRole(dynamic value) {
  if (value is bool) return value ? 'Beifahrer' : 'Fahrer';
  return value?.toString();
}

String? _mapWorkType(dynamic value) {
  if (value is! num) return value?.toString();
  switch (value.toInt()) {
    case 0:
      return 'Ruhe';
    case 1:
      return 'Bereitschaft';
    case 2:
      return 'Arbeit';
    case 3:
      return 'Fahren';
    default:
      return value.toString();
  }
}

String _display(String? value) => (value != null && value.isNotEmpty) ? value : '–';

String? _mapCountry(dynamic value) {
  if (value is! num) return value?.toString();
  final code = value.toInt();
  const names = {
    0: 'No information available',
    1: 'Austria',
    2: 'Albania',
    3: 'Andorra',
    4: 'Armenia',
    5: 'Azerbaijan',
    6: 'Belgium',
    7: 'Bulgaria',
    8: 'Bosnia Herzegovina',
    9: 'Belarus',
    10: 'Switzerland',
    11: 'Cyprus',
    12: 'Czech Republic',
    13: 'Germany',
    14: 'Denmark',
    15: 'Spain',
    16: 'Estonia',
    17: 'France',
    18: 'Finland',
    19: 'Liechtenstein',
    20: 'Faroe Islands (no longer used)',
    21: 'United Kingdom',
    22: 'Georgia',
    23: 'Greece',
    24: 'Hungary',
    25: 'Croatia',
    26: 'Italy',
    27: 'Ireland',
    28: 'Iceland',
    29: 'Kazakhstan',
    30: 'Luxembourg',
    31: 'Lithuania',
    32: 'Latvia',
    33: 'Malta',
    34: 'Monaco',
    35: 'Moldova',
    36: 'North Macedonia',
    37: 'Norway',
    38: 'Netherlands',
    39: 'Portugal',
    40: 'Poland',
    41: 'Romania',
    42: 'San Marino',
    43: 'Russia',
    44: 'Sweden',
    45: 'Slovakia',
    46: 'Slovenia',
    47: 'Turkmenistan',
    48: 'Türkiye',
    49: 'Ukraine',
    50: 'Vatican City',
    51: 'Yugoslavia (no longer used)',
    52: 'Montenegro',
    53: 'Serbia',
    54: 'Uzbekistan',
    55: 'Tajikistan',
    56: 'Kyrgyz Republic',
    57: 'Israel',
    253: 'European Community',
    254: 'Rest of Europe',
    255: 'Rest of the World',
  };
  if (names.containsKey(code)) return names[code];
  if (code >= 58 && code <= 252) return 'Reserved';
  return code.toString();
}

String? _mapEntryType(dynamic value) {
  if (value is! num) return value?.toString();
  return switch (value.toInt()) {
    1 => 'Ende (Kartenauszug/Eingabezeit)',
    _ => value.toString(),
  };
}

Map<String, dynamic> _fullCardFrom(dynamic container) {
  if (container is Map<String, dynamic>) {
    final full = container['full_card_number'];
    if (full is Map<String, dynamic>) {
      return full;
    }
  }
  return const {};
}

String? _decodeAscii(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is List) {
    try {
      final ints = value.whereType<num>().map((e) => e.toInt()).toList();
      return String.fromCharCodes(ints).trim();
    } catch (_) {
      return value.toString();
    }
  }
  if (value is Map && value['value'] is List) {
    return _decodeAscii(value['value']);
  }
  return value.toString();
}

Map<String, dynamic> _mapCalibrationRecord(Map<String, dynamic> c) {
  final card = _fullCardFrom(c['workshop_card_number']);
  final vehicleReg = (c['vehicle_registration_identification'] as Map<String, dynamic>?);
  return {
    'purpose': _mapCalibrationPurpose(c['calibration_purpose']),
    'workshopName': _decodeAscii(c['workshop_name']),
    'workshopAddress': _decodeAscii(c['workshop_address']),
    'cardType': _mapCardType(card['card_type']),
    'cardCountry': _mapCountry(card['card_issuing_member_state']),
    'cardNumber': card['card_number']?.toString(),
    'cardExpiry': c['workshop_card_expiry_date']?.toString(),
    'vin': _decodeAscii(c['vehicle_identification_number']),
    'plateCountry': _mapCountry(vehicleReg?['vehicle_registration_nation']),
    'plate': vehicleReg?['vehicle_registration_number']?.toString(),
    'vehicleConstant': c['w_vehicle_characteristic_constant']?.toString(),
    'equipmentConstant': c['k_constant_of_recording_equipment']?.toString(),
    'tyreCircumference': c['l_tyre_circumference']?.toString(),
    'tyreSize': _decodeAscii(c['tyre_size']),
    'authorisedSpeed': c['authorised_speed']?.toString(),
    'oldOdometer': c['old_odometer_value']?.toString(),
    'newOdometer': c['new_odometer_value']?.toString(),
    'oldTime': c['old_time_value']?.toString(),
    'newTime': c['new_time_value']?.toString(),
    'nextCalibration': c['next_calibration_date']?.toString(),
  };
}

String? _mapCalibrationPurpose(dynamic value) {
  if (value is! num) return value?.toString();
  return switch (value.toInt()) {
    1 => 'Aktivierung',
    2 => 'Ersteinbau',
    3 => 'Einbau',
    _ => value.toString(),
  };
}

String _cardStringFrom(dynamic container) {
  final card = _fullCardFrom(container);
  if (card.isEmpty) return '–';
  final type = _mapCardType(card['card_type']) ?? '–';
  final country = _mapCountry(card['card_issuing_member_state']) ?? '–';
  final number = card['card_number']?.toString() ?? '–';
  return '$type / $country / $number';
}

String? _mapEventType(dynamic value) {
  if (value is! num) return value?.toString();
  return switch (value.toInt()) {
    4 => 'Lenken ohne geeignete Karte',
    10 => 'Datenkonflikt Fahrzeugbewegung',
    _ => value.toString(),
  };
}

String? _mapOverSpeedEventType(dynamic value) {
  if (value is! num) return value?.toString();
  return switch (value.toInt()) {
    7 => 'Geschwindigkeitsüberschreitung',
    _ => value.toString(),
  };
}
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.title,
    required this.child,
    required this.isEmpty,
    required this.emptyText,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool isEmpty;
  final String emptyText;
  final bool initiallyExpanded;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
              const SizedBox(width: 6),
              Text(widget.title, style: text.titleMedium),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_expanded)
          widget.isEmpty
              ? Text(widget.emptyText, style: text.bodyMedium)
              : widget.child,
      ],
    );
  }
}
