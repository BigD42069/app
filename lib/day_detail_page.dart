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
            child: _CardDetailsList(cards: activity.cards, expandable: true),
            collapsible: false,
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Tägliche Aktivitäten',
            isEmpty: activity.activities.isEmpty,
            collapsible: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActivityCharts(entries: activity.activities, cards: activity.cards),
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
                      borderCrossings: activity.borderCrossings,
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
            _item('Grenzübergang', const Color(0xFF8e24aa)),
          ],
        ),
      ),
    );
  }
}

class _CardDetailsList extends StatelessWidget {
  const _CardDetailsList({required this.cards, required this.expandable});
  final List<CardRow> cards;
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    final visibleCards = _dedupeCards(cards);
    return Column(
      children: [
        for (final card in visibleCards)
          _CardDetailsTile(card: card, expandable: expandable),
      ],
    );
  }

  List<CardRow> _dedupeCards(List<CardRow> input) {
    final seen = <String>{};
    final result = <CardRow>[];
    for (final card in input) {
      final number = card.number?.trim();
      if (number == null || number.isEmpty) {
        result.add(card);
        continue;
      }
      if (seen.add(number)) {
        result.add(card);
      }
    }
    return result;
  }
}

class _CardDetailsTile extends StatefulWidget {
  const _CardDetailsTile({required this.card, required this.expandable});
  final CardRow card;
  final bool expandable;

  @override
  State<_CardDetailsTile> createState() => _CardDetailsTileState();
}

class _CardDetailsTileState extends State<_CardDetailsTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = false;
  }

  @override
  void didUpdateWidget(covariant _CardDetailsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandable != widget.expandable && !widget.expandable) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final card = widget.card;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.expandable ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
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
            if (widget.expandable && _expanded) ...[
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
            if (widget.expandable) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.center,
                child: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: cs.onSurface.withOpacity(0.55),
                ),
              ),
            ],
          ],
        ),
      ),
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
  const _ActivityCharts({required this.entries, required this.cards});
  final List<ActivityRow> entries;
  final List<CardRow> cards;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    bool isCoDriverEntry(ActivityRow entry) {
      final flag = entry.isCoDriver;
      if (flag != null) return flag;
      return _isCoDriverRole(entry.role);
    }

    final driverEntries = entries.where((e) => !isCoDriverEntry(e)).toList();
    final coDriverEntries = entries.where((e) => isCoDriverEntry(e)).toList();

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

    Widget chartBlock(String title, List<ActivityRow> source) {
      final intervals = _buildIntervals(source);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 200,
            child: box(
              intervals.isEmpty
                  ? Center(child: Text('Keine Daten vorhanden.', style: text.bodyMedium))
                  : CustomPaint(painter: _ActivityChartPainter(intervals, Theme.of(context)), child: Container()),
            ),
          ),
        ],
      );
    }

    final cardTimeline = _buildCardTimeline(cards);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LegendRow(
          items: const [
            _LegendItem('Ruhe', Colors.blue),
            _LegendItem('Bereitschaft', Colors.yellow),
            _LegendItem('Arbeiten', Colors.purple),
            _LegendItem('Fahren', Colors.red),
          ],
        ),
        const SizedBox(height: 8),
        if (cardTimeline.isNotEmpty) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in cardTimeline) Text(entry, style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
        ],
        chartBlock('Fahrer', driverEntries),
        const SizedBox(height: 12),
        chartBlock('Beifahrer', coDriverEntries),
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
      _drawInterval(canvas, chartRect, interval, _workTypeColor(interval.workType, interval.activity));
    }
    _drawGrid(canvas, chartRect, theme.textTheme);
    _drawXAxis(canvas, chartRect, theme.textTheme);
  }

  @override
  bool shouldRepaint(covariant _ActivityChartPainter oldDelegate) =>
      oldDelegate.intervals != intervals || oldDelegate.theme != theme;
}

void _drawGrid(Canvas canvas, Rect rect, TextTheme textTheme) {
  final gridPaint = Paint()
    ..color = Colors.black.withOpacity(0.5)
    ..strokeWidth = 0.6;
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
        style: textTheme.bodySmall?.copyWith(color: Colors.black.withOpacity(0.7)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left - tp.width - 6, y - tp.height / 2));
  }
}

void _drawXAxis(Canvas canvas, Rect rect, TextTheme textTheme) {
  final textStyle = textTheme.bodySmall?.copyWith(color: Colors.black.withOpacity(0.7));
  final tp = TextPainter(textDirection: TextDirection.ltr);
  final hourWidth = rect.width / 24;
  final labelShift = (hourWidth * 0.25).clamp(3.0, 8.0).toDouble();
  for (int h = 0; h < 24; h += 2) {
    final text = TextSpan(text: h.toString(), style: textStyle);
    tp.text = text;
    tp.layout();
    final shift = h == 0 ? labelShift * 2.35 : labelShift * 1.6;
    final x = rect.left + h * hourWidth - tp.width / 2 + shift;
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
        final minutes = _activityMinutes(e);
        if (minutes == null) return null;
        return _IntervalStart(minutes, e.activity ?? '', e.workType);
      })
      .whereType<_IntervalStart>()
      .toList()
    ..sort((a, b) => a.minutes.compareTo(b.minutes));
  if (parsed.isEmpty) return [];

  final result = <_Interval>[];
  for (var i = 0; i < parsed.length; i++) {
    final start = parsed[i];
    final nextMinutes = i + 1 < parsed.length ? parsed[i + 1].minutes : 24 * 60;
    final startMinutes = start.minutes.clamp(0, 24 * 60).toDouble();
    final endMinutes = nextMinutes.clamp(start.minutes, 24 * 60).toDouble();
    if (endMinutes <= startMinutes) continue;
    result.add(_Interval(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      activity: start.activity,
      workType: start.workType,
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

Color _workTypeColor(int? workType, String? fallbackLabel) {
  if (workType != null) {
    return switch (workType) {
      0 => Colors.blue,
      1 => Colors.yellow,
      2 => Colors.purple,
      3 => Colors.red,
      _ => Colors.grey,
    };
  }
  final l = fallbackLabel?.toLowerCase() ?? '';
  if (l.contains('ruhe')) return Colors.blue;
  if (l.contains('bereit')) return Colors.yellow;
  if (l.contains('arbeit') || l.contains('work')) return Colors.purple;
  if (l.contains('fahr')) return Colors.red;
  return Colors.grey;
}

int? _activityMinutes(ActivityRow entry) {
  final minutes = entry.minutes;
  if (minutes != null) return minutes;
  final dt = _parseActivityTime(entry.time);
  if (dt != null) return dt.hour * 60 + dt.minute;
  return null;
}

List<String> _buildCardTimeline(List<CardRow> cards) {
  final items = <_CardInterval>[];
  final seen = <String>{};
  for (final card in cards) {
    final start = _parseActivityTime(card.insertion);
    final end = _parseActivityTime(card.withdrawal);
    if (start == null && end == null) continue;
    final key = [
      card.number ?? '',
      card.insertion ?? '',
      card.withdrawal ?? '',
    ].join('|');
    if (!seen.add(key)) continue;
    items.add(
      _CardInterval(
        label: _cardLabel(card),
        start: start,
        end: end,
      ),
    );
  }

  items.sort((a, b) {
    final aStart = a.start;
    final bStart = b.start;
    if (aStart == null && bStart == null) return 0;
    if (aStart == null) return 1;
    if (bStart == null) return -1;
    return aStart.compareTo(bStart);
  });

  return items
      .map((i) => '${i.label} von ${_clockLabel(i.start)} bis ${_clockLabel(i.end)}')
      .toList();
}

String _cardLabel(CardRow card) {
  final first = card.firstName?.trim();
  final last = card.lastName?.trim();
  if (first != null && first.isNotEmpty && last != null && last.isNotEmpty) {
    return '${first[0].toUpperCase()}. $last';
  }
  if (last != null && last.isNotEmpty) return last;
  final number = card.number?.trim();
  if (number != null && number.isNotEmpty) return number;
  return 'Unbekannt';
}

String _clockLabel(DateTime? time) {
  if (time == null) return '–';
  return '${_two(time.hour)}:${_two(time.minute)}';
}

String _two(int v) => v.toString().padLeft(2, '0');

class _CardInterval {
  _CardInterval({required this.label, required this.start, required this.end});
  final String label;
  final DateTime? start;
  final DateTime? end;
}

class _IntervalStart {
  _IntervalStart(this.minutes, this.activity, this.workType);
  final int minutes;
  final String activity;
  final int? workType;
}

class _Interval {
  _Interval({
    required this.startMinutes,
    required this.endMinutes,
    required this.activity,
    required this.workType,
  });
  final double startMinutes;
  final double endMinutes;
  final String activity;
  final int? workType;
}

bool _isCoDriverRole(String? role) {
  final l = role?.toLowerCase();
  if (l == null || l.isEmpty) return false;
  return l.contains('bei') || l.contains('co');
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

class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.isEmpty,
    required this.child,
    this.collapsible = true,
    this.preview,
    this.tapToToggle = false,
  });

  final String title;
  final bool isEmpty;
  final Widget child;
  final bool collapsible;
  final Widget? preview;
  final bool tapToToggle;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _expanded = widget.title == 'Tägliche Aktivitäten' || widget.title == 'Karte';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = widget.title;
    final showHeaderToggle =
        widget.collapsible && (!widget.tapToToggle || widget.preview == null);
    Widget wrapToggle(Widget child) {
      if (!widget.collapsible || !widget.tapToToggle || _expanded) return child;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _expanded = !_expanded),
        child: child,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeaderToggle)
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
        if (widget.collapsible && !showHeaderToggle && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6),
            child: Text(title, style: text.titleMedium),
          ),
        if (!widget.collapsible && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(title, style: text.titleMedium),
          ),
        if (!widget.collapsible || _expanded) ...[
          if (widget.isEmpty)
            wrapToggle(Text('Keine Daten vorhanden.', style: text.bodyMedium))
          else
            wrapToggle(widget.child),
        ] else ...[
          if (widget.preview != null) ...[
            wrapToggle(widget.preview!),
            if (!widget.tapToToggle) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
