import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'calendar_events_store.dart';

// Einmaliges Warmup des WebView-Engines, damit die erste Anzeige schneller reagiert.
final Future<void> _webViewWarmUp = _warmUpWebView();

Future<void> _warmUpWebView() async {
  try {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString('<html><body></body></html>');
    // Kurzen Moment warten, damit das Engine-Setup abgeschlossen ist.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Controller wird nicht genutzt, nur Init.
  } catch (_) {
    // Warmup ist best-effort.
  }
}

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

const Map<String, String> _countryFlags = {
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
  'Türkiye': '🇹🇷',
  'North Macedonia': '🇲🇰',
};

const int _extraZoomOut = 8;

/// Leaflet-basierte Karte im WebView mit Pins aus den Aktivitäten.
class PlacesMapView extends StatefulWidget {
  const PlacesMapView({
    super.key,
    required this.places,
    required this.gnss,
    required this.loads,
    this.borderCrossings = const [],
    this.showLegend = false,
    this.showFullscreenButton = true,
    this.initialLat,
    this.initialLon,
    this.initialZoom,
  });

  /// Kann aufgerufen werden, um das WebView-Engine vorzuheizen.
  static Future<void> warmUp() => _webViewWarmUp;

  final List<PlaceRow> places;
  final List<GnssRow> gnss;
  final List<LoadRow> loads;
  final List<BorderCrossingRow> borderCrossings;
  final bool showLegend;
  final bool showFullscreenButton;
  final double? initialLat;
  final double? initialLon;
  final double? initialZoom;

  @override
  State<PlacesMapView> createState() => _PlacesMapViewState();
}

class _PlacesMapViewState extends State<PlacesMapView> {
  WebViewController? _controller;
  bool _loadingStarted = false;

  @override
  void initState() {
    super.initState();
    // Warmup bereits parallel starten (best effort).
    _webViewWarmUp;
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant PlacesMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.places != widget.places ||
        oldWidget.gnss != widget.gnss ||
        oldWidget.loads != widget.loads ||
        oldWidget.borderCrossings != widget.borderCrossings) {
      _reloadHtml();
    }
  }

  void _scheduleLoad() {
    if (_loadingStarted) return;
    _loadingStarted = true;
    Future<void>.microtask(() async {
      if (!mounted) return;
      await _webViewWarmUp;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadHtmlString(
          _buildHtml(
            widget.places,
            widget.gnss,
            widget.loads,
            widget.borderCrossings,
            Theme.of(context).colorScheme.secondary,
            initialLat: widget.initialLat,
            initialLon: widget.initialLon,
            initialZoom: widget.initialZoom,
          ),
        );
      if (!mounted) return;
      setState(() {
        _controller = controller;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gestureRecognizers = {
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    };
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.showFullscreenButton ? 16 : 0),
          child: _controller != null
              ? WebViewWidget(
                  controller: _controller!,
                  gestureRecognizers: gestureRecognizers,
                )
              : Container(
                  color: cs.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        ),
        if (widget.showLegend)
          Positioned(
            left: 12,
            bottom: widget.showFullscreenButton ? 12 : 16,
            child: const _LegendCard(),
          ),
        if (widget.showFullscreenButton)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              heroTag: 'map_fullscreen',
              backgroundColor: cs.secondary,
              onPressed: () {
                _openFullscreen();
              },
              child: const Icon(Icons.open_in_full, color: Colors.black),
            ),
          ),
      ],
    );
  }

  Future<void> _openFullscreen() async {
    final view = await _readCurrentView();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: PlacesMapView(
                  places: widget.places,
                  gnss: widget.gnss,
                  loads: widget.loads,
                  borderCrossings: widget.borderCrossings,
                  showLegend: true,
                  showFullscreenButton: false,
                  initialLat: view?.lat,
                  initialLon: view?.lon,
                  initialZoom: view?.zoom,
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FloatingActionButton.small(
                      heroTag: 'map_exit_fullscreen',
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      onPressed: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reloadHtml() {
    if (_controller == null) {
      _scheduleLoad();
      return;
    }
    _controller!.loadHtmlString(
      _buildHtml(
        widget.places,
        widget.gnss,
        widget.loads,
        widget.borderCrossings,
        Theme.of(context).colorScheme.secondary,
        initialLat: widget.initialLat,
        initialLon: widget.initialLon,
        initialZoom: widget.initialZoom,
      ),
    );
  }

  Future<({double lat, double lon, double zoom})?> _readCurrentView() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final raw = await controller.runJavaScriptReturningResult(
        '(() => { if (typeof map === "undefined") return null; var c = map.getCenter(); return JSON.stringify({lat:c.lat, lon:c.lng, zoom: map.getZoom()}); })();',
      );
      Map<String, dynamic>? decoded;
      if (raw == null) return null;
      if (raw is String) {
        decoded = jsonDecode(raw) as Map<String, dynamic>?;
      } else if (raw is Map) {
        decoded = raw.map((key, value) => MapEntry(key.toString(), value));
      }
      final lat = (decoded?['lat'] as num?)?.toDouble();
      final lon = (decoded?['lon'] as num?)?.toDouble();
      final zoom = (decoded?['zoom'] as num?)?.toDouble();
      if (lat == null || lon == null || zoom == null) return null;
      return (lat: lat, lon: lon, zoom: zoom);
    } catch (_) {
      return null;
    }
  }

  String _buildHtml(
    List<PlaceRow> places,
    List<GnssRow> gnss,
    List<LoadRow> loads,
    List<BorderCrossingRow> borderCrossings,
    Color accent, {
    double? initialLat,
    double? initialLon,
    double? initialZoom,
  }) {
    final points = _collectPoints(places, gnss, loads, borderCrossings);
    final fitPoints = _fitPoints(gnss, points);
    final fitStart = fitPoints.$1;
    final fitEnd = fitPoints.$2;
    final fitStartJs = fitStart != null ? '[${fitStart.lat}, ${fitStart.lon}]' : 'null';
    final fitEndJs = fitEnd != null ? '[${fitEnd.lat}, ${fitEnd.lon}]' : 'null';
    final markersJs = StringBuffer();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final popup = jsonEncode(p.popup ?? p.label);
      markersJs.writeln(
        """
        var m = L.marker(
          [${p.lat}, ${p.lon}],
          {
            title: $popup,
            icon: L.divIcon({
              className: 'pin',
              html: '<div class=\"pin-circle\" style=\"background:${p.color};\">${p.label}</div>',
              iconSize: [30, 30],
              iconAnchor: [15, 30],
            })
          }
        ).addTo(map).bindPopup($popup);
        registerMarker(m);
        markers.push(m);
        """,
      );
    }
    final accentHex = _colorToHex(accent);
    final textHex = _textColorFor(accent);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extraZoomOut = _extraZoomOut;
    final initialCenterJs = (initialLat != null && initialLon != null)
        ? '[${initialLat.toStringAsFixed(8)}, ${initialLon.toStringAsFixed(8)}]'
        : 'null';
    final initialZoomJs = initialZoom != null ? initialZoom.toStringAsFixed(4) : 'null';

    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <style>
      html, body, #map { height: 100%; margin: 0; padding: 0; }
      #map { }
      .leaflet-tile-pane { filter: ${isDark ? 'invert(0.9) hue-rotate(180deg)' : 'none'}; }
      .leaflet-marker-pane { filter: none !important; }
      .leaflet-overlay-pane { filter: none !important; }
      .pin-circle {
        background: $accentHex;
        color: $textHex;
        width: 28px;
        height: 28px;
        border-radius: 14px;
        text-align: center;
        line-height: 28px;
        font-weight: 700;
        border: 2px solid #fff;
        box-shadow: 0 2px 6px rgba(0,0,0,0.35);
      }
      .pin,
      .pin * {
        pointer-events: auto;
      }
      .pin {
        cursor: pointer;
      }
    </style>
  </head>
  <body>
    <div id="map"></div>
    <script>
      var map = L.map('map', { zoomControl: false, zoomSnap: 0.25, zoomDelta: 0.25, tap: false });
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 18,
        minZoom: 0,
      }).addTo(map);
      var markers = [];
      function registerMarker(m) {
        if (m && m._icon) {
          m._icon.style.pointerEvents = 'auto';
          m._icon.style.cursor = 'pointer';
        }
        function openPopup(e) {
          if (e && e.originalEvent && e.originalEvent.stopPropagation) {
            e.originalEvent.stopPropagation();
          }
          if (!m.isPopupOpen || !m.isPopupOpen()) {
            m.openPopup();
          }
        }
        m.on('click', openPopup);
        m.on('touchend', openPopup);
        m.on('keypress', function(e) {
          var key = e && e.originalEvent && e.originalEvent.key;
          if (key === 'Enter' || key === ' ') {
            openPopup(e);
          }
        });
      }
      var fitStart = $fitStartJs;
      var fitEnd = $fitEndJs;
      var extraZoomOut = $extraZoomOut;
      var initialCenter = $initialCenterJs;
      var initialZoom = $initialZoomJs;
      $markersJs
      function boundsFromMarkers() {
        var bounds = null;
        for (var i = 0; i < markers.length; i++) {
          var ll = markers[i].getLatLng();
          if (!bounds) {
            bounds = L.latLngBounds([ll]);
          } else {
            bounds.extend(ll);
          }
        }
        return bounds;
      }
      function applyInitial() {
        if (initialCenter !== null && initialZoom !== null) {
          map.setView(initialCenter, initialZoom);
          return true;
        }
        if (initialCenter !== null) {
          map.setView(initialCenter);
          return true;
        }
        return false;
      }
      function fitMarkers() {
        var bounds = null;
        if (markers.length > 0) {
          bounds = boundsFromMarkers();
        } else if (fitStart && fitEnd) {
          var start = L.latLng(fitStart[0], fitStart[1]);
          var end = L.latLng(fitEnd[0], fitEnd[1]);
          bounds = L.latLngBounds([start, end]);
        }
        if (bounds) {
          var padded = bounds.pad(0.2);
          map.fitBounds(padded, { padding: [32, 32], maxZoom: 15 });
          map.zoomOut(extraZoomOut);
        } else {
          map.fitWorld();
          map.zoomOut(extraZoomOut);
        }
      }
      var appliedInitial = applyInitial();
      if (!appliedInitial) {
        fitMarkers();
      }
      map.whenReady(() => { map.invalidateSize(); if (!appliedInitial) { fitMarkers(); } });
      setTimeout(() => { map.invalidateSize(); if (!appliedInitial) { fitMarkers(); } }, 300);
    </script>
  </body>
</html>
''';
  }

  List<_Point> _collectPoints(
    List<PlaceRow> places,
    List<GnssRow> gnss,
    List<LoadRow> loads,
    List<BorderCrossingRow> borderCrossings,
  ) {
    final entries = <(_Point, DateTime)>[];
    void add(
      String? timeStr,
      String? latStr,
      String? lonStr,
      String color, {
      String? popup,
    }) {
      final lat = double.tryParse(latStr ?? '');
      final lon = double.tryParse(lonStr ?? '');
      if (lat == null || lon == null) return;
      final dt = _tryParse(timeStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      entries.add((_Point(lat, lon, color: color, popup: popup), dt));
    }

    for (final p in places) {
      add(p.entryTime, p.lat, p.lon, '#1e88e5'); // blue
    }
    for (final g in gnss) {
      add(g.time ?? g.gpsTime, g.lat, g.lon, '#f6c400'); // yellow
    }
    for (final l in loads) {
      final op = (l.operationType ?? '').toLowerCase();
      final isUnload = op.contains('2') || op.contains('ent') || op.contains('unload');
      final color = isUnload ? '#e53935' : '#43a047'; // rot entladen, grün beladen
      add(l.time ?? l.gpsTime, l.lat, l.lon, color);
    }
    for (final b in borderCrossings) {
      add(
        b.time,
        b.lat,
        b.lon,
        '#8e24aa',
        popup: _borderCrossingLabel(b),
      );
    }

    entries.sort((a, b) => a.$2.compareTo(b.$2));
    final seen = <String>{};
    final points = <_Point>[];
    int idx = 1;
    for (final e in entries) {
      final key = '${e.$1.lat.toStringAsFixed(6)}:${e.$1.lon.toStringAsFixed(6)}';
      if (seen.contains(key)) continue;
      seen.add(key);
      final label = idx.toString();
      final popup = (e.$1.popup != null && e.$1.popup!.isNotEmpty) ? e.$1.popup! : label;
      points.add(_Point(
        e.$1.lat,
        e.$1.lon,
        label: label,
        color: e.$1.color,
        popup: popup,
      ));
      idx++;
    }
    return points;
  }

  (_Point?, _Point?) _fitPoints(
    List<GnssRow> gnss,
    List<_Point> fallbackPoints,
  ) {
    final gpsEntries = <(_Point, DateTime)>[];
    for (final g in gnss) {
      final lat = double.tryParse(g.lat ?? '');
      final lon = double.tryParse(g.lon ?? '');
      if (lat == null || lon == null) continue;
      final dt = _tryParse(g.time ?? g.gpsTime) ?? DateTime.fromMillisecondsSinceEpoch(0);
      gpsEntries.add((_Point(lat, lon), dt));
    }
    if (gpsEntries.isNotEmpty) {
      gpsEntries.sort((a, b) => a.$2.compareTo(b.$2));
      return (gpsEntries.first.$1, gpsEntries.last.$1);
    }
    if (fallbackPoints.isNotEmpty) {
      return (fallbackPoints.first, fallbackPoints.last);
    }
    return (null, null);
  }

  String _colorToHex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}';

  String _textColorFor(Color c) {
    final luminance = 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue;
    return luminance > 186 ? '#000000' : '#ffffff';
  }

  DateTime? _tryParse(String? value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value).toUtc();
    } catch (_) {
      return null;
    }
  }

  String _borderCrossingLabel(BorderCrossingRow row) {
    final left = _countryLabel(row.countryLeft);
    final entered = _countryLabel(row.countryEntered);
    if (left == null && entered == null) return 'Grenzübergang';
    if (left == null) return entered!;
    if (entered == null) return left;
    return '$left -> $entered';
  }

  String? _countryLabel(String? raw) {
    final name = _countryName(raw);
    if (name == null || name.isEmpty) return null;
    final flag = _countryFlag(name);
    return flag != null ? '$flag $name' : name;
  }

  String? _countryName(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final code = int.tryParse(raw);
    if (code == null) return raw;
    return _countryLookup[code] ?? raw;
  }

  String? _countryFlag(String name) => _countryFlags[name];
}

class _LegendCard extends StatelessWidget {
  const _LegendCard();

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
      color: cs.surface.withOpacity(0.9),
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _item('Manueller Log', const Color(0xFF1e88e5)),
            const SizedBox(height: 4),
            _item('Automatischer Log', const Color(0xFFf6c400)),
            const SizedBox(height: 4),
            _item('Beladen', const Color(0xFF43a047)),
            const SizedBox(height: 4),
            _item('Entladen', const Color(0xFFe53935)),
            const SizedBox(height: 4),
            _item('Grenzübergang', const Color(0xFF8e24aa)),
          ],
        ),
      ),
    );
  }
}

class _Point {
  _Point(
    this.lat,
    this.lon, {
    this.label = '',
    this.color = '#1e88e5',
    this.popup,
  });
  final double lat;
  final double lon;
  final String label;
  final String color;
  final String? popup;
}
