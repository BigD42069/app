import 'package:flutter/material.dart';

import 'calendar_events_store.dart';
import 'places_map_view.dart';

const Map<int, String> _countryLookup = {
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
  20: 'Faroe Islands',
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
  51: 'Yugoslavia',
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

class DayDetailPage extends StatelessWidget {
  const DayDetailPage({super.key, required this.activity, this.events});

  final DayActivity activity;
  final EventBundle? events;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dateLabel =
        '${activity.date.day.toString().padLeft(2, '0')}.${activity.date.month.toString().padLeft(2, '0')}.${activity.date.year.toString().padLeft(4, '0')}';

    bool _hasCoord(String? lat, String? lon) =>
        double.tryParse(lat ?? '') != null && double.tryParse(lon ?? '') != null;
    final hasCoordinates = activity.places.any((p) => _hasCoord(p.lat, p.lon)) ||
        activity.gnss.any((g) => _hasCoord(g.lat, g.lon)) ||
        activity.loads.any((l) => _hasCoord(l.lat, l.lon));

    return Scaffold(
      appBar: AppBar(title: Text(dateLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Fahreraktivität', style: text.titleMedium),
          const SizedBox(height: 8),
          _Section(
            title: 'Kartendaten',
            isEmpty: activity.cards.isEmpty,
            collapsible: true,
            preview: _CardDetailsList(cards: activity.cards, previewOnly: true),
            child: _CardDetailsList(cards: activity.cards),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Tägliche Aktivitäten',
            isEmpty: activity.activities.isEmpty,
            collapsible: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActivityCharts(entries: activity.activities),
              ],
            ),
          ),
          if (events != null) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Fehler und Ereignisse',
              isEmpty: false,
              collapsible: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (events!.faults.isNotEmpty)
                    _buildTable(
                      context,
                      columns: const [
                        'Fehlertyp',
                        'Zweck',
                        'Beginn',
                        'Ende',
                        'Karte Fahrer Beginn',
                        'Karte Fahrer Ende',
                        'Karte Beifahrer Beginn',
                        'Karte Beifahrer Ende',
                      ],
                      rows: events!.faults
                          .map((f) => [
                                f.faultType,
                                f.purpose,
                                _formatDateTime(f.begin) ?? f.begin,
                                _formatDateTime(f.end) ?? f.end,
                                f.driverBegin,
                                f.driverEnd,
                                f.coDriverBegin,
                                f.coDriverEnd,
                              ])
                          .toList(),
                    ),
                  if (events!.faults.isNotEmpty && (events!.events.isNotEmpty || events!.overSpeeds.isNotEmpty))
                    const SizedBox(height: 10),
                  if (events!.events.isNotEmpty)
                    _buildTable(
                      context,
                      columns: const [
                        'Ereignistyp',
                        'Grund',
                        'Beginn',
                        'Ende',
                        'Ähnliche Ereignisse',
                        'Karte Fahrer Beginn',
                        'Karte Fahrer Ende',
                      ],
                      rows: events!.events
                          .map((e) => [
                                e.eventType,
                                e.purpose,
                                _formatDateTime(e.begin) ?? e.begin,
                                _formatDateTime(e.end) ?? e.end,
                                e.similarCount,
                                e.driverBegin,
                                e.driverEnd,
                              ])
                          .toList(),
                    ),
                  if (events!.events.isNotEmpty && events!.overSpeeds.isNotEmpty)
                    const SizedBox(height: 10),
                  if (events!.overSpeeds.isNotEmpty)
                    _buildTable(
                      context,
                      columns: const [
                        'Ereignistyp',
                        'Grund',
                        'Beginn',
                        'Ende',
                        'Max. Geschwindigkeit',
                        'Ø Geschwindigkeit',
                        'Ähnliche Ereignisse',
                        'Karte Fahrer Beginn',
                      ],
                      rows: events!.overSpeeds
                          .map((o) => [
                                o.eventType,
                                o.purpose,
                                _formatDateTime(o.begin) ?? o.begin,
                                _formatDateTime(o.end) ?? o.end,
                                o.maxSpeed,
                                o.avgSpeed,
                                o.similarCount,
                                o.driverBegin,
                              ])
                          .toList(),
                    ),
                ],
              ),
            ),
          ],
          if (hasCoordinates) ...[
            const SizedBox(height: 16),
            _Section(
              title: 'Karte',
              isEmpty: false,
              collapsible: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _MapLegend(),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 320,
                    child: PlacesMapView(
                      places: activity.places,
                      gnss: activity.gnss,
                      loads: activity.loads,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTable(
    BuildContext context, {
    required List<String> columns,
    required List<List<String?>> rows,
  }) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
        rows: rows
            .map(
              (r) => DataRow(
                cells: r.map((v) => DataCell(Text(v ?? '–'))).toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _infoTile(BuildContext context, String label, String value) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7))),
          const SizedBox(height: 4),
          Text(value, style: text.titleMedium),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Text _item(String label, Color color) {
      return Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
              ),
            ),
            TextSpan(text: label),
          ],
          style: TextStyle(color: cs.onSurface, fontSize: 12),
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _item('Manueller Log', const Color(0xFF1e88e5)),
            _item('Automatischer Log', const Color(0xFFf6c400)),
            _item('Beladen', const Color(0xFF43a047)),
            _item('Entladen', const Color(0xFFe53935)),
          ],
        ),
      ),
    );
  }
}

class _CardDetailsList extends StatelessWidget {
  const _CardDetailsList({required this.cards, this.previewOnly = false});
  final List<CardRow> cards;
  final bool previewOnly;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final card in cards)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
            ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Vorname', card.firstName, text),
                _detailRow('Nachname', card.lastName, text),
                _detailRow('Kartentyp', card.type, text),
                _detailRow('Kartenausstellungsland', _countryLabel(card.country), text),
                _detailRow('Kartennummer', card.number, text),
                if (!previewOnly) ...[
                  if (card.number != null) const Divider(height: 18),
                  _detailRow('Gültig bis', _formatDate(card.expiry) ?? _formatDateTime(card.expiry) ?? card.expiry, text),
                  _detailRow('Von', _formatDateTime(card.insertion) ?? card.insertion, text),
                  _detailRow('Bis', _formatDateTime(card.withdrawal) ?? card.withdrawal, text),
                  _detailRow('Km bei Einschub', card.odoInsertion, text),
                  _detailRow('Km bei Entnahme', card.odoWithdrawal, text),
                  _detailRow('Gefahrene Kilometer', _drivenKm(card.odoInsertion, card.odoWithdrawal), text),
                  _detailRow('Land letztes Fahrzeug', _countryLabel(card.prevNation), text),
                  _detailRow('Kennzeichen letztes Fahrzeug', card.prevPlate, text),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _detailRow(String label, String? value, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value ?? '–', style: text.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ActivityCharts extends StatelessWidget {
  const _ActivityCharts({required this.entries});
  final List<ActivityRow> entries;

  @override
  Widget build(BuildContext context) {
    final intervals = _buildIntervals(entries);
    if (intervals.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;

    Widget box(Widget child) {
      final cs = Theme.of(context).colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LegendRow(
          items: const [
            _LegendItem('Arbeit', Colors.redAccent),
            _LegendItem('Ruhe', Colors.blue),
            _LegendItem('Bereitschaft', Colors.yellow),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: box(CustomPaint(painter: _ActivityChartPainter(intervals, Theme.of(context)), child: Container())),
        ),
        const SizedBox(height: 12),
        Text('Fahrzeugführung', style: text.titleSmall),
        const SizedBox(height: 4),
        _LegendRow(
          items: const [
            _LegendItem('Fahrer', Colors.purpleAccent),
            _LegendItem('Beifahrer', Colors.green),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 160,
          child: box(CustomPaint(painter: _RoleChartPainter(intervals, Theme.of(context)), child: Container())),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.items});
  final List<_LegendItem> items;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: items
          .map(
            (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: i.color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Text(i.label, style: text.bodySmall),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _LegendItem {
  const _LegendItem(this.label, this.color);
  final String label;
  final Color color;
}

class _ActivityChartPainter extends CustomPainter {
  _ActivityChartPainter(this.intervals, this.theme);
  final List<_Interval> intervals;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = theme.colorScheme;
    const yLabelWidth = 32.0;
    final chartRect = Rect.fromLTWH(yLabelWidth, 0, size.width - yLabelWidth, size.height - 20);
    canvas.drawRect(chartRect, Paint()..color = cs.surface);
    for (final interval in intervals) {
      _drawInterval(canvas, chartRect, interval, _activityColor(interval.activity));
    }
    _drawGrid(canvas, chartRect, cs, theme.textTheme, yLabelWidth);
    _drawXAxis(canvas, chartRect, cs, theme.textTheme);
  }

  @override
  bool shouldRepaint(covariant _ActivityChartPainter oldDelegate) =>
      oldDelegate.intervals != intervals || oldDelegate.theme != theme;
}

class _RoleChartPainter extends CustomPainter {
  _RoleChartPainter(this.intervals, this.theme);
  final List<_Interval> intervals;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final cs = theme.colorScheme;
    const yLabelWidth = 32.0;
    final chartRect = Rect.fromLTWH(yLabelWidth, 0, size.width - yLabelWidth, size.height - 20);
    canvas.drawRect(chartRect, Paint()..color = cs.surface);
    for (final interval in intervals) {
      _drawInterval(canvas, chartRect, interval, _roleColor(interval.role));
    }
    _drawGrid(canvas, chartRect, cs, theme.textTheme, yLabelWidth);
    _drawXAxis(canvas, chartRect, cs, theme.textTheme);
  }

  @override
  bool shouldRepaint(covariant _RoleChartPainter oldDelegate) =>
      oldDelegate.intervals != intervals || oldDelegate.theme != theme;
}

void _drawGrid(Canvas canvas, Rect rect, ColorScheme cs, TextTheme textTheme, double yLabelWidth) {
  final gridPaint = Paint()
    ..color = cs.onSurface.withOpacity(0.22)
    ..strokeWidth = 1;
  final hourWidth = rect.width / 24;
  // Vertikal: Stunden
  for (int h = 0; h <= 24; h++) {
    final x = rect.left + h * hourWidth;
    canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
  }
  // Horizontal: alle 10 Minuten
  for (int m = 0; m <= 60; m += 10) {
    final y = rect.bottom - (m / 60) * rect.height;
    canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    final tp = TextPainter(
      text: TextSpan(
        text: m.toString(),
        style: textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left - tp.width - 6, y - tp.height / 2));
  }
}

void _drawXAxis(Canvas canvas, Rect rect, ColorScheme cs, TextTheme textTheme) {
  final textStyle = textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7));
  final tp = TextPainter(textDirection: TextDirection.ltr);
  final hourWidth = rect.width / 24;
  for (int h = 2; h <= 24; h += 2) {
    final text = TextSpan(text: h.toString(), style: textStyle);
    tp.text = text;
    tp.layout();
    final x = rect.left + h * hourWidth - tp.width / 2 - 6;
    final y = rect.bottom + 2;
    tp.paint(canvas, Offset(x, y));
  }
}

void _drawInterval(Canvas canvas, Rect rect, _Interval interval, Color color) {
  final hourWidth = rect.width / 24;
  final paint = Paint()..color = color;
  double start = interval.startMinutes;
  while (start < interval.endMinutes) {
    final hour = start ~/ 60;
    final hourStart = hour * 60;
    final hourEnd = hourStart + 60;
    final segStart = start;
    final segEnd = interval.endMinutes.clamp(hourStart.toDouble(), hourEnd.toDouble()).toDouble();
    if (segEnd <= segStart) break;
    final x = rect.left + hourWidth * hour;
    final yStart = rect.top + ((segStart - hourStart) / 60) * rect.height;
    final yEnd = rect.top + ((segEnd - hourStart) / 60) * rect.height;
    canvas.drawRect(Rect.fromLTRB(x, yStart, x + hourWidth, yEnd), paint);
    start = segEnd;
  }
}

List<_Interval> _buildIntervals(List<ActivityRow> entries) {
  final parsed = entries
      .map((e) {
        final dt = _parseActivityTime(e.time);
        return dt == null ? null : _IntervalStart(dt, e.activity ?? '', e.role ?? '');
      })
      .whereType<_IntervalStart>()
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  if (parsed.isEmpty) return [];
  final baseMidnight = DateTime(parsed.first.time.year, parsed.first.time.month, parsed.first.time.day);
  double minutesFromBase(DateTime t) => t.difference(baseMidnight).inMilliseconds / 60000.0;

  final result = <_Interval>[];
  for (var i = 0; i < parsed.length; i++) {
    final start = parsed[i];
    final end = i + 1 < parsed.length ? parsed[i + 1].time : baseMidnight.add(const Duration(hours: 24));
    final startMinutes = minutesFromBase(start.time).clamp(0.0, 24 * 60.0);
    double endMinutes = minutesFromBase(end);
    if (endMinutes < startMinutes) endMinutes = startMinutes;
    if (endMinutes > 24 * 60) endMinutes = 24 * 60.0;
    result.add(_Interval(
      startMinutes: startMinutes.toDouble(),
      endMinutes: endMinutes.toDouble(),
      activity: start.activity,
      role: start.role,
    ));
  }
  return result;
}

DateTime? _parseActivityTime(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value).toLocal();
  } catch (_) {
    return null;
  }
}

String? _countryName(String? raw) {
  if (raw == null) return null;
  final code = int.tryParse(raw);
  if (code == null) return raw;
  return _countryLookup[code] ?? raw;
}

String? _countryLabel(String? raw) {
  final name = _countryName(raw);
  if (name == null) return null;
  final flag = _countryFlag(name);
  return flag != null ? '$flag $name' : name;
}

String? _countryFlag(String name) {
  // Minimal Emoji Mapping für häufige Länder in Tachograph-Daten.
  const flags = {
    'Germany': '🇩🇪',
    'Poland': '🇵🇱',
    'Austria': '🇦🇹',
    'Switzerland': '🇨🇭',
    'France': '🇫🇷',
    'Spain': '🇪🇸',
    'Italy': '🇮🇹',
    'Denmark': '🇩🇰',
    'Netherlands': '🇳🇱',
    'Belgium': '🇧🇪',
    'Czech Republic': '🇨🇿',
    'Hungary': '🇭🇺',
    'Slovakia': '🇸🇰',
    'Slovenia': '🇸🇮',
    'Norway': '🇳🇴',
    'Sweden': '🇸🇪',
    'Finland': '🇫🇮',
    'Lithuania': '🇱🇹',
    'Latvia': '🇱🇻',
    'Estonia': '🇪🇪',
    'Ireland': '🇮🇪',
    'United Kingdom': '🇬🇧',
    'Portugal': '🇵🇹',
    'Luxembourg': '🇱🇺',
    'Greece': '🇬🇷',
    'Croatia': '🇭🇷',
    'Romania': '🇷🇴',
    'Bulgaria': '🇧🇬',
    'Serbia': '🇷🇸',
    'Montenegro': '🇲🇪',
    'Ukraine': '🇺🇦',
    'Russia': '🇷🇺',
    'Turkey': '🇹🇷',
  };
  return flags[name];
}

String? _operationTypeLabel(String? raw) {
  if (raw == null) return null;
  final code = int.tryParse(raw);
  final n = code ?? -1;
  return switch (n) {
    1 => 'Beladen',
    2 => 'Entladen',
    3 => 'Be-/Entladen',
    _ => 'RFU',
  };
}

String? _formatDateTime(String? raw) {
  if (raw == null) return null;
  DateTime? dt;
  try {
    dt = DateTime.parse(raw).toLocal();
  } catch (_) {
    return raw;
  }
  String two(int v) => v.toString().padLeft(2, '0');
  final day = two(dt.day);
  final month = two(dt.month);
  final year = dt.year.toString().padLeft(4, '0');
  final h = two(dt.hour);
  final m = two(dt.minute);
  final s = two(dt.second);
  return '$day.$month.$year $h:$m:$s';
}

String? _formatDate(String? raw) {
  if (raw == null) return null;
  DateTime? dt;
  try {
    dt = DateTime.parse(raw).toLocal();
  } catch (_) {
    final sepIndex = raw.indexOf(RegExp(r'[ T]'));
    if (sepIndex > 0) return raw.substring(0, sepIndex);
    return raw;
  }
  String two(int v) => v.toString().padLeft(2, '0');
  final day = two(dt.day);
  final month = two(dt.month);
  final year = dt.year.toString().padLeft(4, '0');
  return '$day.$month.$year';
}

Color _activityColor(String name) {
  final l = name.toLowerCase();
  if (l.contains('ruhe')) return Colors.blue;
  if (l.contains('bereit')) return Colors.yellow.shade700;
  if (l.contains('arbeit') || l.contains('work') || l.contains('fahr')) return Colors.redAccent;
  return Colors.grey;
}

Color _roleColor(String name) {
  final l = name.toLowerCase();
  if (l.contains('fahrer') && !l.contains('bei')) return Colors.purpleAccent;
  if (l.contains('bei')) return Colors.green;
  return Colors.purpleAccent.withOpacity(0.2);
}

String? _dateOnly(String? raw) {
  if (raw == null) return null;
  try {
    final dt = DateTime.parse(raw);
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    // fallback: cut at space or T
    final sepIndex = raw.indexOf(RegExp(r'[ T]'));
    if (sepIndex > 0) return raw.substring(0, sepIndex);
    return raw;
  }
}

String? _drivenKm(String? start, String? end) {
  final s = double.tryParse(start ?? '');
  final e = double.tryParse(end ?? '');
  if (s == null || e == null) return null;
  final diff = e - s;
  return diff.toStringAsFixed(0);
}

class _IntervalStart {
  _IntervalStart(this.time, this.activity, this.role);
  final DateTime time;
  final String activity;
  final String role;
}

class _Interval {
  _Interval({
    required this.startMinutes,
    required this.endMinutes,
    required this.activity,
    required this.role,
  });
  final double startMinutes;
  final double endMinutes;
  final String activity;
  final String role;
}
class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.isEmpty,
    required this.child,
    this.collapsible = true,
    this.preview,
  });

  final String title;
  final bool isEmpty;
  final Widget child;
  final bool collapsible;
  final Widget? preview;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _expanded = widget.title == 'Tägliche Aktivitäten' || widget.title == 'Karte';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = widget.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.collapsible)
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (title.isNotEmpty) Text(title, style: text.titleMedium),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!widget.collapsible && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(title, style: text.titleMedium),
          ),
        if (!widget.collapsible || _expanded) ...[
          if (widget.isEmpty)
            Text('Keine Daten vorhanden.', style: text.bodyMedium)
          else
            widget.child,
        ] else ...[
          if (widget.preview != null) ...[
            widget.preview!,
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
            ),
          ],
        ],
      ],
    );
  }
}
