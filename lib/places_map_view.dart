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

/// Leaflet-basierte Karte im WebView mit Pins aus den Aktivitäten.
class PlacesMapView extends StatefulWidget {
  const PlacesMapView({
    super.key,
    required this.places,
    required this.gnss,
    required this.loads,
    this.showFullscreenButton = true,
  });

  /// Kann aufgerufen werden, um das WebView-Engine vorzuheizen.
  static Future<void> warmUp() => _webViewWarmUp;

  final List<PlaceRow> places;
  final List<GnssRow> gnss;
  final List<LoadRow> loads;
  final bool showFullscreenButton;

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
        oldWidget.loads != widget.loads) {
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
            Theme.of(context).colorScheme.secondary,
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
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.showFullscreenButton ? 16 : 0),
          child: _controller != null
              ? WebViewWidget(
                  controller: _controller!,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
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
        if (widget.showFullscreenButton)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              heroTag: 'map_fullscreen',
              backgroundColor: cs.secondary,
              onPressed: _openFullscreen,
              child: const Icon(Icons.open_in_full, color: Colors.black),
            ),
          ),
      ],
    );
  }

  void _openFullscreen() {
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
                  showFullscreenButton: false,
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
        Theme.of(context).colorScheme.secondary,
      ),
    );
  }

  String _buildHtml(
    List<PlaceRow> places,
    List<GnssRow> gnss,
    List<LoadRow> loads,
    Color accent,
  ) {
    final points = _collectPoints(places, gnss, loads);
    final markersJs = StringBuffer();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      markersJs.writeln(
        """
        var m = L.marker(
          [${p.lat}, ${p.lon}],
          {
            title: '${p.label}',
            icon: L.divIcon({
              className: 'pin',
              html: '<div class=\"pin-circle\" style=\"background:${p.color};\">${p.label}</div>',
              iconSize: [30, 30],
              iconAnchor: [15, 30],
            })
          }
        ).addTo(map).bindPopup('${p.label}');
        markers.push(m);
        """,
      );
    }
    final centerLat = points.isNotEmpty ? points.first.lat : 0;
    final centerLon = points.isNotEmpty ? points.first.lon : 0;
    final accentHex = _colorToHex(accent);
    final textHex = _textColorFor(accent);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
    </style>
  </head>
  <body>
    <div id="map"></div>
    <script>
      var map = L.map('map', { zoomControl: false });
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 18,
        minZoom: 3,
      }).addTo(map);
      var markers = [];
      $markersJs
      if (markers.length === 1) {
        map.setView(markers[0].getLatLng(), 17);
      } else if (markers.length > 1) {
        var group = L.featureGroup(markers);
        map.fitBounds(group.getBounds().pad(0.005), { maxZoom: 17 });
      } else {
        map.setView([$centerLat, $centerLon], 12);
      }
      map.whenReady(() => { map.invalidateSize(); });
      setTimeout(() => map.invalidateSize(), 300);
    </script>
  </body>
</html>
''';
  }

  List<_Point> _collectPoints(
      List<PlaceRow> places, List<GnssRow> gnss, List<LoadRow> loads) {
    final entries = <(_Point, DateTime)>[];
    void add(String? timeStr, String? latStr, String? lonStr, String color) {
      final lat = double.tryParse(latStr ?? '');
      final lon = double.tryParse(lonStr ?? '');
      if (lat == null || lon == null) return;
      final dt = _tryParse(timeStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
      entries.add((_Point(lat, lon, color: color), dt));
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

    entries.sort((a, b) => a.$2.compareTo(b.$2));
    final seen = <String>{};
    final points = <_Point>[];
    int idx = 1;
    for (final e in entries) {
      final key = '${e.$1.lat.toStringAsFixed(6)}:${e.$1.lon.toStringAsFixed(6)}';
      if (seen.contains(key)) continue;
      seen.add(key);
      points.add(_Point(e.$1.lat, e.$1.lon, label: idx.toString(), color: e.$1.color));
      idx++;
    }
    return points;
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
}

class _LegendCard extends StatelessWidget {
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
          ],
        ),
      ),
    );
  }
}

class _Point {
  _Point(this.lat, this.lon, {this.label = '', this.color = '#1e88e5'});
  final double lat;
  final double lon;
  final String label;
  final String color;
}
