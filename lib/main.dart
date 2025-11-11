// ignore_for_file: prefer_const_literals_to_create_immutables, prefer_const_constructors

/* -----------------------------------------------------------------------------
 * Kalender-App Haupteinstiegspunkt
 * ---------------------------------------------------------------------------
 * Diese Datei bündelt den kompletten Einstiegspunkt der Flutter-Anwendung samt
 * Laufzeitkonfiguration. Hier werden:
 *   • globale Services initialisiert (Theming, Benachrichtigungen, BLE).
 *   • mehrere Persistenz-Layer (Theme-, Auth- und Transfer-Storage) definiert.
 *   • Hilfsklassen für Responsive Layouting, UI-Komponenten und BLE-Scanning
 *     bereitgestellt.
 *   • das eigentliche MaterialApp-Widget mitsamt Navigation, Kalender-Ansicht
 *     und Such-Overlay aufgebaut.
 * Die Datei ist bewusst in Themenblöcke gegliedert, sodass eng verwandte
 * Klassen nebeneinanderstehen und durch ausführliche Kommentare begleitet
 * werden. So lässt sich nachvollziehen, wie Datenfluss, State-Handling und UI
 * zusammenspielen.
 *
 * Inhaltsverzeichnis (zur schnelleren Orientierung):
 *   1. Anwendungseinstieg & Bootstrap (main + globale Singletons)
 *   2. Farb- und Theme-Management (AppPalette → ThemeController)
 *   3. Persistenzlayer für Auth/Transfers sowie Notification-Service
 *   4. BLE-Funktionen & Responsive Utility
 *   5. App-Shell, Search-Overlay und Seiten (Kalender, Liste, Plus, Settings)
 *   6. Dialoge/Widgets (Login, PillLink, ProgressRing, etc.)
 *   7. Onboarding inkl. Custom Painter Szenen
 * ---------------------------------------------------------------------------*/

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File, IOSink;
import 'dart:math';
import 'dart:ui';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // <- debugPrint
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'parser_test_page.dart';

/* =============================================================================
   Anwendungseinstieg & Bootstrap
   -----------------------------------------------------------------------------
   Die main()-Funktion wird von der Flutter-Engine aufgerufen und bereitet alle
   globalen Services vor, bevor das erste Widget gerendert wird. Dazu gehören:
   1) Initialisierung des NotificationService (inkl. Zeitzonen-Daten).
   2) Laden der zuletzt gespeicherten Theme-Palette aus SharedPreferences.
   3) Aufbau eines ThemeController, der per InheritedWidget (ThemeProvider)
      im gesamten Widgetbaum verfügbar gemacht wird.
   Erst danach wird die eigentliche App via runApp() gestartet.
==============================================================================*/

Future<void> main() async {
  // Stellt sicher, dass WidgetsBinding und Plattformkanäle vor async-Calls
  // initialisiert sind. Pflicht bei await in main().
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Timezone-Daten und Notification-Plugin vorbereiten. Dadurch kann der
  //    NotificationService später sofort Erinnerungen planen.
  tz.initializeTimeZones();
  await NotificationService.instance.init();

  // 2) Persistierte Theme-Farben laden. Falls noch keine Werte vorhanden sind,
  //    wird die definierte Fallback-Palette verwendet.
  final themeStorage = ThemeStorage();
  final initialPalette = await themeStorage.loadPalette(
    fallback: AppPalette(accent: const Color(0xFFD4AF37), mode: ThemeMode.dark),
  );

  // 3) ThemeController erstellen und über einen Provider für alle Widgets
  //    verfügbar machen. Dadurch kann z. B. die Einstellungen-Seite die Farbe
  //    ändern und sofort eine Aktualisierung triggern.
  final themeController = ThemeController(initialPalette, themeStorage);

  // --- App-weites Signal, wenn neue DDD-Datei gespeichert wurde ---
  final ValueNotifier<int> dddInboxVersion = ValueNotifier<int>(0);

  runApp(
    ThemeProvider(controller: themeController, child: const KalenderApp()),
  );
}

/* =============================================================================
   Farbschema zur Laufzeit: Model + Controller + Provider
==============================================================================*/

/// Schlanke Datenklasse für die App-Farben.
///
/// Sie speichert nur die Werte, die der Nutzer konfigurieren kann: Akzentfarbe
/// und ThemeMode (hell/dunkel/system). Dadurch bleiben Serialisierung und
/// Persistenz trivial.
class AppPalette {
  AppPalette({required this.accent, this.mode = ThemeMode.dark});

  /// Primärfarbe, die z. B. Buttons, Slider und Highlights einfärbt.
  Color accent;

  /// Ausgewählter Theme-Modus. Standard ist Dark, um mit dem bisherigen Look
  /// kompatibel zu bleiben.
  ThemeMode mode;

  /// Erzeugt eine Kopie mit überschriebenen Feldern (klassisches copyWith).
  AppPalette copyWith({Color? accent, ThemeMode? mode}) =>
      AppPalette(accent: accent ?? this.accent, mode: mode ?? this.mode);
}

/// Controller verwaltet Palette und persistiert Änderungen.
/// WICHTIG: _update() schreibt nur bei echten Änderungen.
class ThemeController extends ChangeNotifier {
  ThemeController(this._palette, this._storage);
  AppPalette _palette;
  final ThemeStorage _storage;

  /// Aktuelle Palette, z. B. für AnimatedBuilder.
  AppPalette get palette => _palette;

  /// Bequemer Zugriff auf den aktuellen ThemeMode.
  ThemeMode get mode => _palette.mode;

  /// Konsolidierter Update-Punkt: prüft auf Änderungen, benachrichtigt Hörer
  /// und speichert anschließend persistente Daten.
  void _update(AppPalette next) {
    // No-Op, wenn sich nichts geändert hat
    if ((next.accent.value == _palette.accent.value) &&
        (next.mode == _palette.mode)) {
      return;
    }
    _palette = next;
    notifyListeners();
    // Persistieren (fire-and-forget)
    _storage.savePalette(_palette);
  }

  // Accent -----------------------------------------------------------------
  void setAccent(Color color) => _update(_palette.copyWith(accent: color));
  void applyPresetGold() => setAccent(const Color(0xFFD4AF37));
  void applyPresetBlue() => setAccent(const Color(0xFF4EA2C9));
  void applyPresetGreen() => setAccent(const Color(0xFF65C94E));
  void applyPresetPink() => setAccent(const Color(0xFFE15BA6));

  // ThemeMode --------------------------------------------------------------
  void setThemeMode(ThemeMode m) => _update(_palette.copyWith(mode: m));
  void toggleTheme() =>
      setThemeMode(mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

/// InheritedNotifier: einfacher Zugriff auf den Controller überall im Widgetbaum
class ThemeProvider extends InheritedNotifier<ThemeController> {
  const ThemeProvider({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Lookup-Helfer, der den Controller aus dem Widgetbaum zieht. Durch das
  /// assert fällt ein fehlender Provider sofort im Debug-Modus auf.
  static ThemeController of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(provider != null, 'ThemeProvider not found in widget tree.');
    return provider!.notifier!;
  }
}

/// Persistenz-Layer (SharedPreferences) – lazy Singleton-Instance
class ThemeStorage {
  static const _kAccent = 'accent_argb';
  static const _kMode = 'theme_mode';

  // Ein SharedPreferences-Handle für die gesamte App-Laufzeit
  final Future<SharedPreferences> _sp = SharedPreferences.getInstance();

  Future<void> savePalette(AppPalette p) async {
    final sp = await _sp;
    // Farbe wird als ARGB-Integer gespeichert, um Präzision zu behalten.
    await sp.setInt(_kAccent, p.accent.value);
    // ThemeMode nutzt die Enum-Namen als eindeutige Strings.
    await sp.setString(_kMode, p.mode.name); // 'light' | 'dark' | 'system'
  }

  Future<AppPalette> loadPalette({required AppPalette fallback}) async {
    final sp = await _sp;
    final int? argb = sp.getInt(_kAccent);
    final String? modeStr = sp.getString(_kMode);

    final ThemeMode mode = switch (modeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => fallback.mode,
    };

    final Color accent = argb != null ? Color(argb) : fallback.accent;
    return AppPalette(accent: accent, mode: mode);
  }
}

/// --- Einfache Auth-/First-Run-Persistenz ---
class AuthStorage {
  static const _kFirstShown = 'first_run_prompt_shown';
  static const _kLoggedIn = 'logged_in';
  static const _kUsername = 'username';

  final Future<SharedPreferences> _sp = SharedPreferences.getInstance();

  /// Prüft, ob der First-Run-Dialog bereits angezeigt wurde.
  Future<bool> firstPromptShown() async =>
      (await _sp).getBool(_kFirstShown) ?? false;

  /// Markiert den First-Run-Dialog als gesehen.
  Future<void> setPromptShown() async =>
      (await _sp).setBool(_kFirstShown, true);

  /// Gibt zurück, ob ein Nutzer eingeloggt ist.
  Future<bool> isLoggedIn() async => (await _sp).getBool(_kLoggedIn) ?? false;

  /// Persistiert Login-Status und den eingegebenen Nutzernamen.
  Future<void> setLoggedIn(String username) async {
    final sp = await _sp;
    await sp.setBool(_kLoggedIn, true);
    await sp.setString(_kUsername, username);
  }

  /// Löscht Login-Zustand und gespeicherten Nutzernamen.
  Future<void> logout() async {
    final sp = await _sp;
    await sp.setBool(_kLoggedIn, false);
    await sp.remove(_kUsername);
  }
}

final authStorage = AuthStorage();
final transferStorage = TransferStorage();

// 👇 DIESE ZEILE FEHLT BEI DIR
final ValueNotifier<int> dddInboxVersion = ValueNotifier<int>(0);

class TransferStorage {
  static const _kLastTransferAt = 'last_transfer_at';
  final Future<SharedPreferences> _sp = SharedPreferences.getInstance();

  /// Speichert den aktuellen Zeitpunkt als letzte Übertragung.
  Future<void> setLastTransferNow() async {
    final sp = await _sp;
    await sp.setInt(_kLastTransferAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Liest den letzten Übertragungszeitpunkt oder `null`, falls keiner vorhanden.
  Future<DateTime?> getLastTransfer() async {
    final sp = await _sp;
    final ms = sp.getInt(_kLastTransferAt);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

// ===== NotificationService (DROP-IN) =====
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'transfer_reminder_v2'; // neue ID => frischer Kanal
  static const _channelName = 'Transfer Reminder';
  static const _channelDesc = 'Erinnert an die Dateiübertragung';
  static const _defaultId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _inited = false;

  /// Öffnet (falls nötig) die Systemeinstellungen für "Exact Alarms" auf
  /// Android, damit geplante Notifications zuverlässig zugestellt werden.
  Future<void> openExactAlarmSettingsIfNeeded() async {
    if (!Platform.isAndroid) return;
    // Einfach immer öffnen, wenn geplant & nix ankommt:
    const intent = AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
      data: 'package:com.example.dateiexplorer_tachograph',
    );
    await intent.launch();
  }

  /// Initialisiert das Plugin einmalig (Kanäle, iOS-Permissions etc.).
  Future<void> init() async {
    if (_inited) return;

    // Zeitzonen einmalig
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      // wichtig für Banner, wenn App im Vordergrund ist:
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Kanal mit MAX Importance anlegen (neue ID!)
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(channel);

    _inited = true;
  }

  /// Kümmert sich darum, dass die App auf allen Plattformen Notifications
  /// anzeigen darf. Auf iOS wird aktiv nachgefragt, auf Android ggf. zum
  /// Systemeinstellungsbildschirm weitergeleitet.
  Future<bool> ensurePermissions() async {
    await init();

    if (Platform.isIOS) {
      final ok = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }

    if (Platform.isAndroid) {
      // POST_NOTIFICATIONS via permission_handler
      var status = await Permission.notification.status;
      if (status.isDenied || status.isRestricted || status.isLimited) {
        status = await Permission.notification.request();
        if (!status.isGranted) return false;
      }

      // App-interner Schalter (Samsung/Kanäle)
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled == false) {
        await openAppSettings(); // führt zur App-Seite
        return false;
      }
      return true;
    }

    return true;
  }

  /// Sofortbenachrichtigung (zum Testen)
  Future<void> pingNow({
    String title = 'Test',
    String body = 'Sofort-Benachrichtigung',
    int id = _defaultId,
  }) async {
    await ensurePermissions();
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: android, iOS: ios);
    await _plugin.show(id, title, body, details);
  }

  /// Geplante Benachrichtigung (beachtet Exact Alarms)
  /// Geplante Benachrichtigung (beachtet Exact Alarms)
  /// Geplante Benachrichtigung (beachtet Exact Alarms)
  Future<void> scheduleIn(
    Duration delay, {
    int id = _defaultId,
    String title = 'Dateiübertragung',
    String body = 'Bitte übertrage deine Dateien erneut.',
  }) async {
    await ensurePermissions();

    // Minimum 1 Minute
    final Duration effectiveDelay = delay >= const Duration(minutes: 1)
        ? delay
        : const Duration(minutes: 1);

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    AndroidScheduleMode? mode;
    try {
      mode = AndroidScheduleMode.exactAllowWhileIdle;
    } catch (_) {
      mode = null;
    }

    Future<void> scheduleNotification({
      required int notificationId,
      required Duration offset,
    }) async {
      final tz.TZDateTime scheduledTime = now.add(offset);
      await _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduledTime,
        details,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: mode,
      );
    }

    final Duration halfDelay = Duration(
      milliseconds: (effectiveDelay.inMilliseconds * 0.5).round(),
    );
    if (halfDelay > Duration.zero && halfDelay < effectiveDelay) {
      await scheduleNotification(notificationId: id + 1, offset: halfDelay);
    }

    final Duration ninetyDelay = Duration(
      milliseconds: (effectiveDelay.inMilliseconds * 0.9).round(),
    );
    if (ninetyDelay > Duration.zero && ninetyDelay < effectiveDelay) {
      await scheduleNotification(notificationId: id + 2, offset: ninetyDelay);
    }

    await scheduleNotification(notificationId: id, offset: effectiveDelay);
  }

  @Deprecated('Nutze scheduleIn(Duration) statt scheduleReminderIn.')
  Future<void> scheduleReminderIn(Duration delay) => scheduleIn(delay);

  /// Hebt eine zuvor geplante Erinnerung wieder auf.
  Future<void> cancelReminder({int id = _defaultId}) async {
    await init();
    await _plugin.cancel(id);
  }
}

/* =============================================================================
   Bluetooth Low Energy (BLE) – Filter & Berechtigungen
   -----------------------------------------------------------------------------
   Hier wird definiert, welche Geräte beim Scan erkannt werden sollen und welche
   Berechtigungen dafür auf Android benötigt werden. Die Filter-Kombination aus
   Service-UUID und optionalem Namenspräfix verhindert, dass sich fremde Geräte
   einblenden. Die Permission-Routine berücksichtigt die seit Android 12
   getrennten Bluetooth-Rechte.
==============================================================================*/

/// Eindeutige Service-UUID, die vom Gerät gesendet wird.
const String kMyServiceUuid = '12345678-1234-5678-1234-56789abcdef0';

/// Optionales Namenspräfix, um die Trefferliste weiter einzugrenzen.
const String kMyNamePrefix = 'TACHO-';

/// UUID der Kontroll-Characteristic, über die Kommandos (GET_FILE etc.) laufen.
const String kMyControlCharUuid = '12345678-1234-5678-1234-56789abcdef1';

/// Dateiname, der beim initialen Abruf vom Gerät angefordert wird.
const String kTransferFileName = '/storage/ddd.DDD';

/// Prüft, ob ein ScanResult zu unserem Gerät gehört.
bool isMyDevice(ScanResult r) {
  // Seit flutter_blue_plus 1.28 werden UUIDs als Guid-Objekte geliefert, daher
  // konvertieren wir zur String-Darstellung und vergleichen case-insensitiv.
  final hasService = r.advertisementData.serviceUuids.any(
    (g) => g.toString().toLowerCase() == kMyServiceUuid.toLowerCase(),
  );

  // Priorisiert den Advertising-Namen, fällt sonst auf den Plattformnamen zurück
  // (z. B. iOS: Geräteliste, Android: Bluetooth-Nickname).
  final name = r.advertisementData.advName.isNotEmpty
      ? r.advertisementData.advName
      : r.device.platformName;

  return hasService &&
      (kMyNamePrefix.isEmpty || name.startsWith(kMyNamePrefix));
}

/// Fordert alle benötigten BLE-Berechtigungen an (Android-spezifisch).
Future<bool> ensureBlePermissions() async {
  // Auf iOS bzw. Desktop greifen andere Mechanismen -> keine Laufzeitanfrage.
  if (!Platform.isAndroid) return true;

  // Android 12+: getrennte Rechte für Scan/Connect. Auf älteren Android-Versionen
  // wird zusätzlich Standort-Zugriff verlangt.
  final toRequest = <Permission>[
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];

  final statuses = await toRequest.request();
  if (statuses.values.any((s) => s.isPermanentlyDenied)) {
    // Sobald der Nutzer ein Recht dauerhaft verweigert hat, leiten wir zu den
    // Systemeinstellungen weiter und brechen mit false ab.
    await openAppSettings();
    return false;
  }

  // Nur wenn alle Permissions gewährt wurden, kehren wir mit true zurück.
  return statuses.values.every((s) => s.isGranted);
}

/* =============================================================================
   Responsive Utility (R)
   -----------------------------------------------------------------------------
   Diese Helper-Klasse ist die zentrale Stelle für Layout-Konstanten. Sie liest
   aktuelle MediaQuery-Werte aus und bietet darauf aufbauend berechnete
   Eigenschaften (Abstände, Höhen, Breakpoints). Sämtliche Widgets greifen
   darüber auf konsistente Maße zu, wodurch Pixelwerte nicht unkontrolliert im
   Code verteilt werden. Die zugehörige Extension erlaubt einfachen Zugriff via
   `context.r` überall im Widgetbaum.
==============================================================================*/

class R {
  R(this.context)
    : size = MediaQuery.of(context).size,
      pad = MediaQuery.of(context).padding,
      textScale = MediaQuery.textScalerOf(context);

  /// Referenz auf den aufrufenden BuildContext, falls später weitere
  /// MediaQuery-Werte benötigt werden.
  final BuildContext context;

  /// Aktuelle Bildschirmgröße; daraus werden Breiten/Höhen abgeleitet.
  final Size size;

  /// Sichere Bereiche (Notch, Home Indicator etc.), um Padding anzupassen.
  final EdgeInsets pad;

  /// Globale Textskalierung des Nutzers (Barrierefreiheit).
  final TextScaler textScale;

  /// Komfortable Getter zur Bildschirmbreite/-höhe.
  double get w => size.width;
  double get h => size.height;

  // --- Breakpoints ---------------------------------------------------------
  bool get ultraNarrow => w < 340;
  bool get narrow => w < 380;
  bool get compact => w < 420;
  bool get medium => w < 600;

  // --- Abstände & Maße -----------------------------------------------------
  double get gutter => w.clamp(320, 480) / 24; // ~13..20px je nach Gerät
  double get space => gutter * 0.75;
  double get headerHLarge => 124 - (compact ? 8 : 0);
  double get headerHWeek => 46 - (compact ? 4 : 0);
  double get bottomBarH => compact ? 56 : 60;
  double get navIconSize => compact ? 20 : 24;
  double get navButtonHeight => compact ? 44 : 48;
  double get searchPillHOpen => compact ? 54 : 60;
  double get searchPillHClose => compact ? 48 : 52;
  double get gridAspect => compact ? 1.25 : 1.35;
  double get dayFont => compact ? 14 : 16;
  double get dotSize => compact ? 8 : 10;
  double get ringSize => (w - (gutter * 2)).clamp(160.0, 240.0);

  /// Abgerundete Pille-Radien, optional kleiner Modus für Buttons etc.
  double pillRadius([bool small = false]) =>
      small ? (compact ? 16 : 18) : (compact ? 20 : 24);
}

extension R_ on BuildContext {
  /// Praktischer Zugriff auf die responsive Helper-Instanz über `context.r`.
  R get r => R(this);
}

/* =============================================================================
   App Root: MaterialApp mit zwei Themes (Light/Dark)
   -----------------------------------------------------------------------------
   - Dark Mode: exakt wie zuvor – tiefschwarzer Hintergrund
   - Light Mode: klassisch weiß/schwarz (keine Beigetöne)
==============================================================================*/

class KalenderApp extends StatelessWidget {
  const KalenderApp({super.key});

  static const Color onBlack = Color(0xFFEDEDED);

  @override
  Widget build(BuildContext context) {
    final themeCtrl = ThemeProvider.of(context);
    return AnimatedBuilder(
      animation: themeCtrl,
      builder: (context, _) {
        final accent = themeCtrl.palette.accent;

        ThemeData mkTheme(Brightness b) {
          // Basis-ColorScheme (Material), danach gezielt überschreiben
          final csSeed = ColorScheme.fromSeed(seedColor: accent, brightness: b);

          // Gemeinsame Textgrößen/Gewichte (Farben gleich danach via apply())
          const baseText = TextTheme(
            headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
            titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            bodyMedium: TextStyle(fontSize: 16),
          );

          if (b == Brightness.dark) {
            // === DARK: exakt wie dein „vorher“ – tiefschwarz, kein Grau
            final cs = csSeed.copyWith(
              surface: const Color(0xFF121212),
              surfaceContainerHighest: const Color(0xFF1E1E1E),
              onSurface: onBlack,
              outlineVariant: Colors.white24,
              secondary: accent,
              secondaryContainer: const Color(0xFF2B2B2B),
            );

            return ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorScheme: cs,
              scaffoldBackgroundColor: Colors.black,
              fontFamily:
                  const CupertinoThemeData().textTheme.textStyle.fontFamily,
              textTheme: baseText.apply(
                bodyColor: cs.onSurface,
                displayColor: cs.onSurface,
              ),
              dividerTheme: const DividerThemeData(
                color: Colors.white12,
                thickness: 1,
              ),
            );
          }

          // === LIGHT: klassisch Weiß/Schwarz (kein Beige)
          final cs = csSeed.copyWith(
            surface: Colors.white,
            surfaceContainerHighest: const Color(0xFFF2F2F2),
            onSurface: Colors.black,
            outlineVariant: Colors.black12,
            secondary: accent,
            secondaryContainer: Colors.black12,
          );

          return ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: cs,
            scaffoldBackgroundColor: Colors.white,
            fontFamily:
                const CupertinoThemeData().textTheme.textStyle.fontFamily,
            textTheme: baseText.apply(
              bodyColor: cs.onSurface,
              displayColor: cs.onSurface,
            ),
            dividerTheme: const DividerThemeData(
              color: Colors.black12,
              thickness: 1,
            ),
          );
        }

        final light = mkTheme(Brightness.light);
        final dark = mkTheme(Brightness.dark);

        return MaterialApp(
          title: 'Kalender',
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          themeMode: themeCtrl.mode,
          home: const Shell(),
        );
      },
    );
  }
}

/* =============================================================================
   App-Shell & Navigation
   -----------------------------------------------------------------------------
   Enthält den Haupt-Shell-Container mit fünf Tabs (Kalender, Liste, Plus,
   Suche, Einstellungen) sowie begleitende Widgets für das Such-Overlay. Diese
   Sektion verwaltet Auth-Gates, Bottom-Navigation und Tastatur-Handling.
==============================================================================*/

/// Rahmen-Widget der Applikation mit Tab-Navigation und globalem Such-Overlay.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

/// Zustandsobjekt verwaltet Tab-Auswahl, Fokus und Authentifizierungs-Gate.
class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int selectedIndex = 0;

  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Bei jedem frischen Start prüfen:
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.ensurePermissions();
      await _showAuthGateIfNeeded(); // << immer checken
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Wenn App wieder in den Vordergrund kommt → erneut prüfen
    if (state == AppLifecycleState.resumed) {
      _showAuthGateIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Öffnet den Onboarding-/Login-Flow, falls noch kein Nutzer angemeldet ist.
  Future<void> _showAuthGateIfNeeded() async {
    if (!mounted) return;
    final loggedIn = await authStorage.isLoggedIn();
    if (loggedIn) return;

    // Full-screen, blocks the app until closed
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => const OnboardingScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );

    // After closing, if still not logged in (e.g., "überspringen"),
    // we simply let the user into the app; next cold start will gate again.
  }

  @override
  Widget build(BuildContext context) {
    // Prüfen, ob Tastatur offen ist, um Bottom-Bar/Overlay dynamisch anzupassen.
    final kbVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: [
            // Inhalt
            IndexedStack(
              index: selectedIndex,
              children: const [
                CalendarHomePage(),
                ListPage(),
                PlusPage(),
                EmptyPage(title: 'Suche'),
                SettingsPage(),
              ],
            ),

            // Bottom-Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: false,
                minimum: EdgeInsets.fromLTRB(
                  context.r.gutter,
                  0,
                  context.r.gutter,
                  context.r.gutter,
                ),
                child: GlassBottomBarSegmented(
                  selectedIndex: selectedIndex,
                  onTap: (i) {
                    // Beim Verlassen der Suche Tastatur sauber schließen
                    if (selectedIndex == 3 && i != 3) {
                      _searchFocus.unfocus();
                    }
                    setState(() => selectedIndex = i);
                    if (i == 3) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _searchFocus.requestFocus();
                      });
                    }
                  },
                  searchMode: selectedIndex == 3,
                  keyboardVisible: kbVisible,
                  searchFocus: _searchFocus,
                  searchController: _searchController,
                ),
              ),
            ),

            // Über Tastatur: die eine Such-Pill
            if (selectedIndex == 3)
              _DockedSearchOverlay(
                focusNode: _searchFocus,
                controller: _searchController,
              ),
          ],
        ),
      ),
    );
  }
}

/* =============================================================================
   Such-Overlay (über der Tastatur)
==============================================================================*/

/* =============================================================================
   Such-Overlay Komponenten
   -----------------------------------------------------------------------------
   Enthält Widgets und Hilfskurven für die animierte Suche, die über der
   Bottom-Bar eingeblendet wird, wenn Tab 3 aktiv ist.
==============================================================================*/

/// Zeigt eine pillenförmige Suchleiste, die über der Bottom-Bar schwebt.
class _SearchOverlayPill extends StatelessWidget {
  const _SearchOverlayPill({
    required this.focusNode,
    required this.controller,
    required this.height,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _GlassSurface(
      radius: 34,
      hpad: 14,
      vpad: 0,
      height: height,
      child: Row(
        children: [
          Icon(
            CupertinoIcons.search,
            size: 20,
            color: cs.onSurface.withOpacity(0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              placeholder: 'suchen...',
              placeholderStyle: TextStyle(color: cs.onSurface.withOpacity(0.5)),
              decoration: const BoxDecoration(color: Colors.transparent),
              style: TextStyle(color: cs.onSurface), // Light Mode: schwarz
              cursorColor: cs.secondary,
              onTapOutside: (_) => focusNode.unfocus(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verpackt das Suchfeld inklusive Animationen für Öffnen/Schließen.
class _DockedSearchOverlay extends StatelessWidget {
  const _DockedSearchOverlay({
    required this.focusNode,
    required this.controller,
  });

  final FocusNode focusNode;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final kbOpen = insets > 0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 40),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: kbOpen ? (insets + 12.0) : context.r.gutter,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final openWidth = constraints.maxWidth - (context.r.gutter * 2);
          const closedWidth = 200.0;

          final beginW = kbOpen ? closedWidth : openWidth;
          final endW = kbOpen ? openWidth : closedWidth;

          final beginH = kbOpen
              ? context.r.searchPillHOpen
              : context.r.searchPillHClose;
          final endH = kbOpen
              ? context.r.searchPillHClose
              : context.r.searchPillHOpen;

          return Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              curve: _IntervalCurve(0.08, 1.0, Curves.easeOutBack),
              tween: Tween<double>(begin: beginW, end: endW),
              builder: (context, width, _) {
                return TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 600),
                  curve: _IntervalCurve(0.08, 1.0, Curves.easeOutBack),
                  tween: Tween<double>(begin: beginH, end: endH),
                  builder: (context, height, __) {
                    return SizedBox(
                      width: width,
                      child: _SearchOverlayPill(
                        focusNode: focusNode,
                        controller: controller,
                        height: height,
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Sanfter „Vorlauf“ innerhalb der Animationsdauer (wirkt hochwertiger)
/// Zeitabschnitt-basierte Curve, die nur innerhalb eines Teilintervalls wirkt.
class _IntervalCurve extends Curve {
  const _IntervalCurve(this.begin, this.end, this.curve)
    : assert(begin >= 0 && end <= 1 && begin < end);

  final double begin;
  final double end;
  final Curve curve;

  @override
  double transformInternal(double t) {
    if (t <= begin) return 0.0;
    if (t >= end) return 1.0;
    final double norm = (t - begin) / (end - begin);
    return curve.transform(norm);
  }
}

/// BackOut mit etwas mehr Overshoot (für Bottom-Bar Animationen)
/// Dehnt die Standard `Curves.easeOutBack` für stärkeres Overshooting.
class _BackMoreOut extends Curve {
  const _BackMoreOut([this.overshoot = 1.6]);
  final double overshoot;
  @override
  double transform(double t) {
    final s = overshoot;
    t -= 1.0;
    return t * t * ((s + 1) * t + s) + 1.0;
  }
}

/* =============================================================================
   Sonstige Seiten
==============================================================================*/

/// Placeholder-Seite für noch nicht implementierte Tabs (z. B. Suche).
class EmptyPage extends StatelessWidget {
  const EmptyPage({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
  );
}

/* =============================================================================
   Listenansicht & Transfer Tab
   -----------------------------------------------------------------------------
   Vereint Platzhalter, Verlaufsübersicht sowie den Plus-Tab, der den BLE-Scan
   und Datei-Transfer anstößt. Enthält Intro/Ergebnis-Views und Hilfswidgets.
==============================================================================*/

/// Stellt vergangene Übertragungen als scrollbare Liste dar.
class ListPage extends StatelessWidget {
  const ListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'Keine Übertragungen verfügbar',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/* =============================================================================
   Plus Page (Intro → Results → Transfer)
   -----------------------------------------------------------------------------
   - Intro: Label/Buttons folgen Theme
   - Results: gleiche Optik
   - Transfer: Text volle Breite, Bluetooth-Icon rechts, Start-Button darunter,
               Progress-Ring responsive (kein Abschneiden auf kleineren Phones)
==============================================================================*/

enum PlusMode { intro, results, transfer }

/// Startseite für den Datei-Transfer inkl. Status- und Ergebnisansichten.
class PlusPage extends StatefulWidget {
  const PlusPage({super.key});
  @override
  State<PlusPage> createState() => _PlusPageState();
}

/// State-Objekt kombiniert Transfer-Fortschritt, BLE-Ergebnisse und Dialoge.
class _PlusPageState extends State<PlusPage> {
  PlusMode mode = PlusMode.intro;

  DateTime? lastScanAt;
  String? connectedDeviceName;
  BluetoothDevice? _connectedDevice;

  // Bluetooth / Scan-State
  bool scanning = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  final List<ScanResult> _results = [];
  StreamSubscription<BluetoothAdapterState>? _stateSub;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  Future<void> _checkPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    // Adapter-Status beobachten (An/Aus etc.)
    _stateSub = FlutterBluePlus.adapterState.listen((s) {
      setState(() => _adapterState = s);
    });
    // Anfangszustand holen
    FlutterBluePlus.adapterState.first.then((s) {
      if (!mounted) return;
      setState(() => _adapterState = s);
    });
  }

  @override
  void dispose() {
    _stopScan();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _onScanPressed() async {
    // 1) Permissions
    if (!await ensureBlePermissions()) {
      _showSnack(context, 'Berechtigungen fehlen.');
      return;
    }

    // 2) Adapter an?
    if (_adapterState != BluetoothAdapterState.on) {
      _showSnack(context, 'Bluetooth ist deaktiviert. Bitte einschalten.');
      setState(() {
        mode = PlusMode.results;
        scanning = false;
        _results.clear();
        lastScanAt = DateTime.now();
      });
      return;
    }

    // 3) UI vorbereiten
    _results.clear();
    setState(() {
      mode = PlusMode.results;
      scanning = true;
      lastScanAt = DateTime.now();
    });

    // 4) Ergebnis-Stream abonnieren (deduplizieren per Remote-ID)
    await _scanResultsSub?.cancel();
    _scanResultsSub = FlutterBluePlus.scanResults.listen((batch) {
      bool changed = false;
      for (final r in batch.where(isMyDevice)) {
        final id = r.device.remoteId.str;
        final idx = _results.indexWhere((e) => e.device.remoteId.str == id);
        if (idx >= 0) {
          if (_results[idx].rssi != r.rssi ||
              _results[idx].advertisementData.advName !=
                  r.advertisementData.advName) {
            _results[idx] = r;
            changed = true;
          }
        } else {
          _results.add(r);
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    }, onError: (e) => _showSnack(context, 'Scanfehler: $e'));

    // 5) Scan starten – nur bekannte Parameter deiner FBP-Version
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(kMyServiceUuid)],
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      _showSnack(context, 'Scan-Start fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    if (mounted) setState(() => scanning = false);
  }

  void _backToIntro() {
    _stopScan();
    setState(() {
      mode = PlusMode.intro;
      _connectedDevice = null;
      connectedDeviceName = null;
    });
  }

  Future<void> _connectTo(ScanResult r) async {
    final dev = r.device;
    _stopScan();
    setState(() {
      connectedDeviceName = _bestName(r);
      _connectedDevice = dev;
      mode = PlusMode.transfer;
    });

    try {
      await dev.connect(timeout: const Duration(seconds: 8));
      // Für deinen Flow reicht „connected“ als Zustand;
      // Dienstsuche kannst du bei Bedarf ergänzen:
      // await dev.discoverServices();
    } catch (e) {
      if (!mounted) return;
      _showSnack(context, 'Verbindung fehlgeschlagen: $e');
      // zurück in die Ergebnisliste, damit der User neu probieren kann
      setState(() {
        mode = PlusMode.results;
        connectedDeviceName = null;
        _connectedDevice = null;
      });
    }
  }

  String _bestName(ScanResult r) {
    final adv = r.advertisementData.advName;
    final plat = r.device.platformName; // kann leer sein
    return (adv.isNotEmpty ? adv : (plat.isNotEmpty ? plat : 'Unbekannt'));
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (mode) {
      case PlusMode.intro:
        child = _IntroView(onScan: _onScanPressed, lastScanAt: lastScanAt);
        break;
      case PlusMode.results:
        child = _ResultsView(
          onBack: _backToIntro,
          scanning: scanning,
          adapterOn: _adapterState == BluetoothAdapterState.on,
          results: _results,
          onConnect: _connectTo,
          onRescan: _onScanPressed,
        );
        break;
      case PlusMode.transfer:
        final device = _connectedDevice;
        child = device == null
            ? _TransferFallback(
                deviceName: connectedDeviceName ?? 'Gerät',
                onBack: () {
                  setState(() {
                    mode = PlusMode.results;
                    _connectedDevice = null;
                    connectedDeviceName = null;
                  });
                  _onScanPressed();
                },
              )
            : _TransferView(
                deviceName: connectedDeviceName ?? 'Gerät',
                device: device,
                onBack: () {
                  // Beim Zurück in die Liste optional erneut scannen
                  setState(() {
                    mode = PlusMode.results;
                    _connectedDevice = null;
                    connectedDeviceName = null;
                  });
                  _onScanPressed();
                },
              );
        break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// Einstiegskachel mit Icons und Erklärungen vor dem ersten Scan.
class _IntroView extends StatelessWidget {
  const _IntroView({required this.onScan, this.lastScanAt});
  final VoidCallback onScan;
  final DateTime? lastScanAt;

  // Bildbreite (du meintest: Größe passt aktuell) – unverändert klein
  double imageWidth(BuildContext c) =>
      (MediaQuery.of(c).size.width * 0.3).clamp(100.0, 160.0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Assets (genau wie deine Datei-Namen)
    const imgFahrerkarteLight = 'assets/images/fahrerkartelight.png';
    const imgFahrerkarteDark = 'assets/images/fahrerkartedark.png';
    const imgAuslesegeraetLight = 'assets/images/auslesegeraetlight.png';
    const imgAuslesegeraetDark = 'assets/images/auslesegeraetdark.png';

    final fahrerkarteAsset = isDark ? imgFahrerkarteDark : imgFahrerkarteLight;
    final auslesegeraetAsset = isDark
        ? imgAuslesegeraetDark
        : imgAuslesegeraetLight;

    final timeText = lastScanAt == null
        ? ''
        : 'Zuletzt gesucht: '
              '${lastScanAt!.hour.toString().padLeft(2, '0')}:'
              '${lastScanAt!.minute.toString().padLeft(2, '0')}:'
              '${lastScanAt!.second.toString().padLeft(2, '0')}';

    Widget divider() => Divider(height: 1, color: cs.outlineVariant);

    // Ein Helfer-Row: Bild linksbündig, optionaler Trailing rechtsbündig,
    // beide auf gleicher Grundlinie (oben) ausgerichtet.
    Widget imageWithOptionalTrailing({
      required String asset,
      Widget? trailing,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bild linksbündig
          Align(
            alignment: Alignment.topLeft,
            child: Image.asset(
              asset,
              width: imageWidth(context),
              fit: BoxFit.contain,
            ),
          ),
          // Abstand und Platzfüller
          const SizedBox(width: 12),
          Expanded(child: const SizedBox()),
          // Optionaler Trailing rechts am Rand
          if (trailing != null)
            Align(alignment: Alignment.topRight, child: trailing),
        ],
      );
    }

    // Stil wie dein bisheriger „Geräte suchen“-Button
    Widget searchButton() {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onScan,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(context.r.pillRadius()),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Text(
            'Geräte suchen',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
      );
    }

    return ListView(
      key: const ValueKey('intro'),
      padding: EdgeInsets.fromLTRB(
        context.r.gutter,
        80,
        context.r.gutter,
        context.r.bottomBarH + context.r.gutter,
      ),
      children: [
        // ─────────────────────────────
        // 1) Tachograph entsperren
        const _StepTitle('1. Tachograph entsperren'),
        const SizedBox(height: 6),
        divider(),
        const SizedBox(height: 10),
        Text(
          'Stecke deine Fahrerkarte in den Tachographen und entsperre das Gerät.',
          style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
        ),
        const SizedBox(height: 12),
        // Bild linksbündig
        imageWithOptionalTrailing(asset: fahrerkarteAsset),
        const SizedBox(height: 28),

        // ─────────────────────────────
        // 2) Verbindung herstellen
        const _StepTitle('2. Verbindung herstellen'),
        const SizedBox(height: 6),
        divider(),
        const SizedBox(height: 10),
        Text(
          'Stecke dein Auslesegerät ein und aktiviere Bluetooth am Smartphone.',
          style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
        ),
        const SizedBox(height: 12),
        // Bild links – Button rechts (gleiche Höhe)
        imageWithOptionalTrailing(
          asset: auslesegeraetAsset,
          trailing: searchButton(),
        ),
        if (timeText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              timeText,
              style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
        const SizedBox(height: 28),

        // ─────────────────────────────
        // 3) Dateiübertragung
        const _StepTitle('3. Dateiübertragung'),
        const SizedBox(height: 6),
        divider(),
        const SizedBox(height: 10),
        Text(
          'Nach erfolgreicher Verbindung kannst du die Dateiübertragung starten.',
          style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
        ),
      ],
    );
  }
}

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}

/// Zeigt Scanresultate sowie Hinweise zum Verbindungsaufbau an.
class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.onBack,
    required this.scanning,
    required this.adapterOn,
    required this.results,
    required this.onConnect,
    required this.onRescan,
  });

  final VoidCallback onBack;
  final bool scanning;
  final bool adapterOn;
  final List<ScanResult> results;
  final void Function(ScanResult r) onConnect;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      key: const ValueKey('results'),
      padding: EdgeInsets.fromLTRB(
        context.r.gutter,
        80,
        context.r.gutter,
        context.r.bottomBarH + context.r.gutter,
      ),
      children: [
        // Back-Pill
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(context.r.pillRadius()),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '<',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Verbindung zu Tachographen',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: Text(
                'Geräte in der Nähe',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onRescan,
              child: Text(
                scanning ? 'Suche…' : 'Erneut suchen',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 12),

        if (!adapterOn)
          _InfoRow(
            icon: Icons.bluetooth_disabled,
            text:
                'Bluetooth ist aus. Bitte in den Systemeinstellungen aktivieren.',
          ),

        if (adapterOn && results.isEmpty && !scanning)
          _InfoRow(
            icon: CupertinoIcons.dot_radiowaves_left_right,
            text:
                'Keine Geräte gefunden. Stelle sicher, dass das Gerät sichtbar ist.',
          ),

        if (scanning)
          _InfoRow(
            icon: CupertinoIcons.dot_radiowaves_left_right,
            text: 'Suche läuft…',
          ),

        // Ergebnisliste
        // NEU (richtig)
        for (final r in results.where(isMyDevice)) ...[
          _BtDeviceRow(
            name: _bestName(r),
            subtitle: 'ID: ${r.device.remoteId.str} · RSSI ${r.rssi} dBm',
            onConnect: () => onConnect(r),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  String _bestName(ScanResult r) {
    final adv = r.advertisementData.advName;
    final plat = r.device.platformName;
    return (adv.isNotEmpty ? adv : (plat.isNotEmpty ? plat : 'Unbekannt'));
  }
}

/// Listenzeile mit Icon + Beschreibung für Kleingedrucktes.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurface.withOpacity(0.9), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spezialisierte Zeile für gefundene BLE-Geräte mit Connect-Button.
class _BtDeviceRow extends StatelessWidget {
  const _BtDeviceRow({
    required this.name,
    required this.subtitle,
    required this.onConnect,
  });
  final String name;
  final String subtitle;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Textspalte
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: cs.outlineVariant),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Icon(
          CupertinoIcons.bluetooth,
          size: 64,
          color: cs.onSurface.withOpacity(0.95),
        ),
        const SizedBox(width: 16),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onConnect,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(context.r.pillRadius()),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'Verbinden',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Generische Darstellung eines BLE-Geräts mit Icon + Zusatzinfos.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    required this.subtitle,
    required this.onConnect,
  });
  final String name;
  final String subtitle;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Textspalte (nutzt volle Breite, solange Icon/Buttons Platz haben)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: cs.outlineVariant),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Icon(
          CupertinoIcons.bluetooth,
          size: 64,
          color: cs.onSurface.withOpacity(0.95),
        ),
        const SizedBox(width: 16),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onConnect,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(context.r.pillRadius()),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'Verbinden',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* --- Dateiübertragung: responsive Ring & Layout (kein Abschneiden mehr) --- */

/// Fallback-Ansicht, falls kein aktives [BluetoothDevice] verfügbar ist (z. B.
/// wenn die Verbindung zwischenzeitlich getrennt wurde).
class _TransferFallback extends StatelessWidget {
  const _TransferFallback({required this.deviceName, required this.onBack});
  final String deviceName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      key: const ValueKey('transfer-fallback'),
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 140),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '<',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Dateiübertragung',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Icon(
          CupertinoIcons.exclamationmark_triangle,
          size: 56,
          color: cs.secondary,
        ),
        const SizedBox(height: 16),
        Text(
          'Keine aktive Verbindung zu $deviceName gefunden.',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Bitte gehe zurück zur Geräteliste und stelle die Verbindung erneut her.',
          style: TextStyle(color: cs.onSurface.withOpacity(0.8), fontSize: 15),
        ),
      ],
    );
  }
}

/// Verwaltung eines laufenden Transfers inklusive Fortschrittsring und
/// Dateianforderung per BLE.
/// Verwaltung eines laufenden Transfers inklusive Fortschrittsring.
class _TransferView extends StatefulWidget {
  const _TransferView({
    required this.deviceName,
    required this.device,
    required this.onBack,
  });
  final String deviceName;
  final BluetoothDevice device;
  final VoidCallback onBack;

  @override
  State<_TransferView> createState() => _TransferViewState();
}

class _TransferViewState extends State<_TransferView> {
  // UI-State
  bool started = false; // Ring sichtbar
  bool done = false; // Ring zeigt "Fertig"
  int runId = 0; // Ring neu starten
  bool _requestInFlight = false;

  // BLE
  BluetoothCharacteristic? _ctrlChar;
  StreamSubscription<List<int>>? _notifySub;

  // Dateitransfer-State
  bool _transferActive = false;
  IOSink? _fileSink;
  String? _savedFilePath;
  int _expectedFileBytes = 0;
  int _receivedFileBytes = 0;

  @override
  void dispose() {
    _notifySub?.cancel();
    _notifySub = null;
    _closeFileSink(deleteFile: false);
    super.dispose();
  }

  // --- BLE Hilfen -----------------------------------------------------------

  Future<void> _ensureConnected() async {
    var state = await widget.device.connectionState.first;
    if (state != BluetoothConnectionState.connected) {
      try {
        await widget.device.connect(timeout: const Duration(seconds: 8));
      } catch (_) {}
      await widget.device.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first;
    }
  }

  Future<void> _prepareCtrlChar() async {
    if (_ctrlChar != null) return;
    await _ensureConnected();
    final services = await widget.device.discoverServices();

    final service = services.firstWhere(
      (s) => s.uuid.toString().toLowerCase() == kMyServiceUuid.toLowerCase(),
      orElse: () => throw StateError('Service $kMyServiceUuid nicht gefunden.'),
    );

    final characteristic = service.characteristics.firstWhere(
      (c) =>
          c.uuid.toString().toLowerCase() == kMyControlCharUuid.toLowerCase(),
      orElse: () => throw StateError(
        'Characteristic $kMyControlCharUuid nicht gefunden.',
      ),
    );

    _ctrlChar = characteristic;
  }

  Future<void> _ensureNotifyListener() async {
    await _prepareCtrlChar();
    final c = _ctrlChar!;
    if (_notifySub != null) return;

    if (c.properties.notify || c.properties.indicate) {
      _notifySub = c.onValueReceived.listen(_onDataFromDevice);
      widget.device.cancelWhenDisconnected(_notifySub!);
      await c.setNotifyValue(true);
    } else {
      throw StateError(
        'Characteristic ${c.uuid} unterstützt keine Notifications.',
      );
    }
  }

  // --- Datenpfad ------------------------------------------------------------

  Future<void> _onDataFromDevice(List<int> bytes) async {
    if (bytes.isEmpty) return;

    final first = bytes.first;
    if (first == 0x7B /* '{' */ ) {
      final msg = utf8.decode(bytes, allowMalformed: true);
      _handleJsonMessage(msg);
    } else {
      if (_transferActive && _fileSink != null) {
        _fileSink!.add(bytes);
        _receivedFileBytes += bytes.length;
        setState(() {}); // Fortschritt sichtbar
      }
    }
  }

  void _handleJsonMessage(String msg) {
    Map<String, dynamic>? obj;
    try {
      obj = jsonDecode(msg) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('JSON parse fail: $e / "$msg"');
      return;
    }

    final type = obj['type']?.toString() ?? '';

    if (type == 'BEGIN') {
      final size = (obj['size'] as num?)?.toInt() ?? 0;
      _startNewFileSink(size);
      return;
    }

    if (type == 'END' || type == 'DONE') {
      _finishTransfer(success: true);
      return;
    }

    if (type == 'ERROR') {
      final stage = obj['stage']?.toString() ?? '';
      final m = obj['msg']?.toString() ?? '';
      _showSnack(context, 'Gerät meldet Fehler: $stage $m');
      _finishTransfer(success: false);
      return;
    }

    if (type == 'CANCELLED') {
      _showSnack(context, 'Übertragung abgebrochen');
      _finishTransfer(success: false);
      return;
    }

    // INFO/META: ignorieren bzw. loggen
    if (type == 'INFO' || type == 'META') {
      debugPrint('INFO/META: $msg');
    }
  }

  Future<void> _startNewFileSink(int expectedBytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // WICHTIG: Großbuchstaben-Extension (Parser filtern oft strikt)
    final path = '${dir.path}/tachograph_$ts.DDD';

    final file = File(path);
    final sink = file.openWrite();

    _expectedFileBytes = expectedBytes;
    _receivedFileBytes = 0;
    _savedFilePath = path;
    _fileSink = sink;
    _transferActive = true;

    if (!mounted) return;
    setState(() {
      started = true;
      done = false;
      runId++;
    });

    debugPrint('Transfer START -> $path ($expectedBytes bytes erwartet)');
  }

  Future<void> _finishTransfer({required bool success}) async {
    final sink = _fileSink;
    final path = _savedFilePath;

    _fileSink = null;
    _transferActive = false;

    if (sink != null) {
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      done = success;
    });

    if (success && path != null) {
      _showSnack(context, 'Datei gespeichert: $path ($_receivedFileBytes B)');
      // → ListPage informieren: neu laden
      dddInboxVersion.value++;
    } else if (!success && path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _closeFileSink({required bool deleteFile}) async {
    final sink = _fileSink;
    final path = _savedFilePath;

    _fileSink = null;
    _transferActive = false;

    if (sink != null) {
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
    }

    if (deleteFile && path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Fehler beim Löschen $path: $e');
      }
    }

    _expectedFileBytes = 0;
    _receivedFileBytes = 0;
    _savedFilePath = null;
  }

  // --- Start-Button ---------------------------------------------------------

  Future<void> start() async {
    if (_requestInFlight) return;
    setState(() => _requestInFlight = true);

    try {
      await _prepareCtrlChar();
      await _ensureNotifyListener();

      final cmd = 'GET_FILE $kTransferFileName'; // z. B. /storage/ddd.DDD
      final data = utf8.encode(cmd);

      final props = _ctrlChar!.properties;
      final canWriteWithRsp = props.write;
      final canWriteNoRsp = props.writeWithoutResponse;

      if (!canWriteWithRsp && !canWriteNoRsp) {
        throw StateError(
          'Characteristic ${_ctrlChar!.uuid} ist nicht schreibbar.',
        );
      }

      await _ctrlChar!.write(
        data,
        withoutResponse: !canWriteWithRsp && canWriteNoRsp,
      );

      await transferStorage.setLastTransferNow();
      await NotificationService.instance.scheduleIn(const Duration(minutes: 1));

      // Warten auf BEGIN → dann startet der Ring in _startNewFileSink()
    } catch (e) {
      if (mounted) _showSnack(context, 'Dateiabfrage fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _requestInFlight = false);
    }
  }

  void _onFinishedRing() {
    // Ring fertig animiert → nichts weiter nötig
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;

        const double padH = 20.0;
        const double padTop = 80.0;

        final double ringByWidth = (w - padH * 2).clamp(160.0, 360.0);
        final double ringByHeight = (h * 0.55).clamp(160.0, 320.0);
        final double ringSize = ringByWidth < ringByHeight
            ? ringByWidth
            : ringByHeight;

        return ListView(
          key: const ValueKey('transfer'),
          padding: const EdgeInsets.fromLTRB(padH, padTop, padH, 140),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.onBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '<',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Dateiübertragung',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),

            Text(
              'Verbunden mit',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.deviceName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Unterstützungstext …',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.80)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  CupertinoIcons.bluetooth,
                  size: 44,
                  color: cs.onSurface.withOpacity(0.95),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: cs.outlineVariant),

            const SizedBox(height: 14),

            Row(
              children: [
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _requestInFlight ? null : start,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      'Dateiübertragung starten',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (_requestInFlight && !started)
              Center(
                child: Column(
                  children: [
                    const CupertinoActivityIndicator(radius: 12),
                    const SizedBox(height: 10),
                    Text(
                      'Dateiabfrage wird an ${widget.deviceName} gesendet…',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                    ),
                  ],
                ),
              ),

            if (started)
              Center(
                child: _ProgressRing(
                  key: ValueKey(runId),
                  duration: const Duration(seconds: 4),
                  onFinished: _onFinishedRing,
                  size: ringSize,
                ),
              ),
            if (started) const SizedBox(height: 8),

            if (_transferActive)
              Text(
                'Empfange Daten... $_receivedFileBytes / $_expectedFileBytes Bytes',
                style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
              ),

            if (!_transferActive && done)
              Text(
                'Übertragung abgeschlossen.',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Animierter Kreis, der verbleibenden Fortschritt visualisiert.
class _ProgressRing extends StatefulWidget {
  const _ProgressRing({
    super.key,
    required this.duration,
    required this.onFinished,
    this.size = 240, // dynamisch überschreibbar (responsive)
  });

  final Duration duration;
  final VoidCallback onFinished;
  final double size;

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

/// Legt Animationscontroller und CustomPainter für den Fortschrittsring an.
class _ProgressRingState extends State<_ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onFinished();
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.secondary;
    final bg = cs.secondaryContainer.withOpacity(0.9);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final value = _ctrl.value; // 0..1
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _RingPainter(
                  progress: value,
                  bg: bg,
                  fg: fg,
                  stroke: (widget.size * 0.09).clamp(14.0, 26.0),
                ),
              ),
              AnimatedScale(
                duration: const Duration(milliseconds: 260),
                scale: value >= 1.0 ? 1.0 : 0.8,
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 260),
                  opacity: value >= 1.0 ? 1.0 : 0.0,
                  child: const Text(
                    'Fertig',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Zeichnet den Ring inklusive Ticks, Fortschrittsbogen und glühender Kante.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.bg,
    required this.fg,
    required this.stroke,
  });
  final double progress; // 0..1
  final Color bg;
  final Color fg;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - stroke / 2;

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = bg;

    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = fg;

    const start = -pi / 2;
    final sweepBg = 2 * pi * 0.85;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      start,
      sweepBg,
      false,
      bgPaint,
    );

    final sweepFg = sweepBg * progress;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      start,
      sweepFg,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.bg != bg ||
      old.fg != fg ||
      old.stroke != stroke;
}

/* =============================================================================
   Kalender-Home (großer Titel + Wochentage + Monatsraster)
==============================================================================*/

/// Hauptkalender mit kombinierter Monats- und Wochenübersicht.
class CalendarHomePage extends StatefulWidget {
  const CalendarHomePage({super.key});
  @override
  State<CalendarHomePage> createState() => _CalendarHomePageState();
}

/// Verwaltet ScrollController, Animationen und Dialoginteraktionen.
class _CalendarHomePageState extends State<CalendarHomePage> {
  final ScrollController _scroll = ScrollController();
  static final DateTime _startMonth = DateTime(2025, 6, 1);
  static final DateTime _endMonth = DateTime(2100, 12, 1);
  late final List<DateTime> months;
  late final List<GlobalKey> _monthKeys;
  late String _visibleMonthText;

  @override
  void initState() {
    super.initState();
    months = _generateMonths(_startMonth, _endMonth);
    _monthKeys = List.generate(months.length, (_) => GlobalKey());
    _visibleMonthText = _fmtMonth(_startMonth);
    _scroll.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
  }

  @override
  void dispose() {
    _scroll.removeListener(_handleScroll);
    _scroll.dispose();
    super.dispose();
  }

  List<DateTime> _generateMonths(
    DateTime startInclusive,
    DateTime endInclusive,
  ) {
    final list = <DateTime>[];
    DateTime cur = DateTime(startInclusive.year, startInclusive.month, 1);
    final end = DateTime(endInclusive.year, endInclusive.month, 1);
    while (!(cur.year == end.year && cur.month == end.month)) {
      list.add(cur);
      cur = DateTime(cur.year, cur.month + 1, 1);
    }
    list.add(end);
    return list;
  }

  void _handleScroll() {
    const headerHeight = 124 + 46; // entspricht den fixed Sliver-Höhen
    DateTime? current;
    for (int i = 0; i < _monthKeys.length; i++) {
      final ctx = _monthKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= headerHeight + 8) {
        current = months[i];
      } else {
        break;
      }
    }
    current ??= months.first;
    final text = _fmtMonth(current);
    if (text != _visibleMonthText) setState(() => _visibleMonthText = text);
  }

  String _fmtMonth(DateTime m) {
    const names = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _LargeTitleHeader(monthText: _visibleMonthText),
        ),
        const SliverPersistentHeader(pinned: true, delegate: _WeekdaysBar()),

        // >>> keine feste Höhe mehr, nur normaler Inhalt
        SliverList.builder(
          itemCount: months.length,
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.symmetric(horizontal: context.r.gutter),
            child: Container(
              key: _monthKeys[i],
              child: MonthSection(
                month: months[i],
                // falls du meinen größeren Look behalten willst:
                // MonthGrid nutzt bereits cellAspect 1.08 in MonthSection
              ),
            ),
          ),
        ),

        // (Optional) kleiner Abschlussabstand
        // SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}

/// Sliver-Header für den großen Monatsnamen inklusive Animationen.
class _LargeTitleHeader extends SliverPersistentHeaderDelegate {
  _LargeTitleHeader({required this.monthText});
  final String monthText;

  @override
  double get minExtent => 124;
  @override
  double get maxExtent => 124;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        context.r.gutter,
        top + 8,
        context.r.gutter,
        10,
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        monthText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LargeTitleHeader old) =>
      old.monthText != monthText;
}

/// Fixierter Header, der die Wochentage im ScrollView anzeigt.
class _WeekdaysBar extends SliverPersistentHeaderDelegate {
  const _WeekdaysBar();
  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: cs.surface.withOpacity(0.82),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.r.gutter,
                  8,
                  context.r.gutter,
                  6,
                ),
                child: const WeekdaysRow(),
              ),
              Divider(height: 1, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _WeekdaysBar old) => false;
}

/// Statischer Wochentagsbalken für nicht-scrollende Layouts.
class WeekdaysRow extends StatelessWidget {
  const WeekdaysRow({super.key});
  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'D', 'M', 'D', 'F', 'S', 'S'];
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(
        7,
        (i) => Expanded(
          child: Center(
            child: Text(
              labels[i],
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                color: cs.onSurface.withOpacity(0.6),
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Verpackt einen Monatsblock inklusive Titel und Grid.
class MonthSection extends StatelessWidget {
  const MonthSection({super.key, required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
            _name(month),
            style: textTheme.titleMedium!.copyWith(
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        MonthGrid(month: month, cellAspect: 0.95), // etwas höher = größer
      ],
    );
  }

  String _name(DateTime m) {
    const names = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];
    return '${names[m.month - 1]} ${m.year}';
  }
}

/* --- MonthGrid optimiert: weniger Lookups/Allokationen pro Zelle ---------- */

/// Baut das Monatsgitter mit Tagen, Markierungen und heutigen Datum.
class MonthGrid extends StatelessWidget {
  const MonthGrid({super.key, required this.month, this.cellAspect});

  final DateTime month;
  final double? cellAspect;

  bool _hasDot(DateTime d) {
    // deterministisches "zufälliges" Muster (wie im Original)
    final seed = d.year * 10000 + d.month * 100 + d.day;
    final rng = Random(seed);
    return rng.nextInt(7) == 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final first = DateTime(month.year, month.month, 1);
    final firstWeekday = (first.weekday + 6) % 7; // Montag = 0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();
    final totalCells = firstWeekday + daysInMonth;
    final rows = (totalCells / 7).ceil();

    Widget divider() => Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      height: 1,
      color: cs.outlineVariant,
    );

    final aspect = cellAspect ?? context.r.gridAspect;

    return Column(
      children: [
        for (int r = 0; r < rows; r++) ...[
          Row(
            children: List.generate(7, (c) {
              final idx = r * 7 + c;
              final dayNum = idx - firstWeekday + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const Expanded(child: SizedBox.shrink());
              }

              final date = DateTime(month.year, month.month, dayNum);
              final isToday =
                  date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              final showDot = _hasDot(date);

              return Expanded(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isToday)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$dayNum',
                              style: textTheme.bodyMedium!.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: context.r.dayFont + 2,
                              ),
                            ),
                          )
                        else
                          Text(
                            '$dayNum',
                            style: textTheme.bodyMedium!.copyWith(
                              fontSize: context.r.dayFont + 2,
                              color: cs.onSurface.withOpacity(0.92),
                            ),
                          ),
                        // fester Slot für den Marker – Zahl bleibt auf gleicher Höhe
                        const SizedBox(height: 3),
                        Opacity(
                          opacity: showDot ? 1 : 0, // behält Größe immer bei
                          child: Container(
                            width: context.r.dotSize + 1,
                            height: context.r.dotSize + 1,
                            decoration: BoxDecoration(
                              color: cs.secondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          if (r < rows - 1) divider(),
        ],
        divider(),
      ],
    );
  }
}

/* =============================================================================
   Bottom Navigation (Glas / responsive)
==============================================================================*/

/// Custom-Bottom-Bar mit Glas-Effekt und integrierter Suchleiste.
class GlassBottomBarSegmented extends StatelessWidget {
  const GlassBottomBarSegmented({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.searchMode = false,
    this.keyboardVisible = false,
    this.searchFocus,
    this.searchController,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool searchMode;
  final bool keyboardVisible;
  final FocusNode? searchFocus;
  final TextEditingController? searchController;

  @override
  Widget build(BuildContext context) {
    final barH = context.r.bottomBarH;
    const gapNormal = 10.0;
    const leftNarrow = 75.0;
    const rightNarrow = 75.0;

    const animDur = Duration(milliseconds: 950);
    const animCurve = _BackMoreOut(1.8);

    return SizedBox(
      height: barH,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (searchMode) {
            // Suchmodus: links Home, rechts Settings, Mitte frei
            return Row(
              children: [
                AnimatedContainer(
                  duration: animDur,
                  curve: animCurve,
                  width: leftNarrow,
                  child: _GlassGroup(
                    radius: 34,
                    hpad: 1,
                    vpad: 6,
                    children: [
                      Expanded(
                        child: Center(
                          child: _NavIcon(
                            icon: CupertinoIcons.house_fill,
                            selected: selectedIndex == 0,
                            onTap: () => onTap(0),
                            iconSize: context.r.navIconSize,
                            buttonHeight: barH,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: animDur,
                  curve: animCurve,
                  width: rightNarrow,
                  child: _GlassGroup(
                    radius: 34,
                    hpad: 1,
                    vpad: 6,
                    children: [
                      Expanded(
                        child: Center(
                          child: _NavIcon(
                            icon: CupertinoIcons.gear_alt_fill,
                            selected: selectedIndex == 4,
                            onTap: () => onTap(4),
                            iconSize: context.r.navIconSize,
                            buttonHeight: barH,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          // Normalmodus: links(3) – mitte(1) – rechts(1)
          return Row(
            children: [
              Expanded(
                flex: 5,
                child: AnimatedContainer(
                  duration: animDur,
                  curve: animCurve,
                  child: _GlassGroup(
                    radius: 34,
                    hpad: 10,
                    vpad: 8,
                    children: [
                      Expanded(
                        child: Center(
                          child: _NavIcon(
                            icon: CupertinoIcons.house_fill,
                            selected: selectedIndex == 0,
                            onTap: () => onTap(0),
                            iconSize: context.r.navIconSize,
                            buttonHeight: context.r.navButtonHeight,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _NavIcon(
                            icon: CupertinoIcons.list_bullet_below_rectangle,
                            selected: selectedIndex == 1,
                            onTap: () => onTap(1),
                            iconSize: context.r.navIconSize,
                            buttonHeight: context.r.navButtonHeight,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _NavIcon(
                            icon: CupertinoIcons.add,
                            selected: selectedIndex == 2,
                            onTap: () => onTap(2),
                            iconSize: context.r.navIconSize,
                            buttonHeight: context.r.navButtonHeight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: gapNormal),

              Expanded(
                flex: 3,
                child: AnimatedContainer(
                  duration: animDur,
                  curve: animCurve,
                  child: Align(
                    alignment: Alignment.center,
                    child: _GlassGroup(
                      radius: 34,
                      children: [
                        _NavIcon(
                          icon: CupertinoIcons.search,
                          selected: selectedIndex == 3,
                          onTap: () => onTap(3),
                          iconSize: context.r.navIconSize,
                          buttonHeight: context.r.navButtonHeight,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: gapNormal),

              Expanded(
                flex: 3,
                child: AnimatedContainer(
                  duration: animDur,
                  curve: animCurve,
                  child: _GlassGroup(
                    radius: 34,
                    hpad: 10,
                    vpad: 8,
                    children: [
                      Expanded(
                        child: Center(
                          child: _NavIcon(
                            icon: CupertinoIcons.gear_alt_fill,
                            selected: selectedIndex == 4,
                            onTap: () => onTap(4),
                            iconSize: context.r.navIconSize,
                            buttonHeight: context.r.navButtonHeight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Einheitliche Glasfläche (Blur + Gradient + Border), folgt Theme
/// Render-Schicht für den Glassmorphism-Hintergrund der Navigation.
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.radius = 34,
    this.hpad = 10,
    this.vpad = 8,
    this.height,
  });

  final Widget child;
  final double radius;
  final double hpad;
  final double vpad;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = cs.onSurface;

    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: hpad, vertical: vpad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: on.withOpacity(0.10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [on.withOpacity(0.12), on.withOpacity(0.06)],
        ),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.35),
          width: 1,
        ),
      ),
      child: child,
    );

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: content,
      ),
    );

    if (height != null) {
      return SizedBox(height: height, child: clipped);
    }
    return clipped;
  }
}

/// Gruppiert Navigations-Icons, Label und optionalen Search-Pill.
class _GlassGroup extends StatelessWidget {
  const _GlassGroup({
    required this.children,
    this.radius = 28,
    this.hpad = 10,
    this.vpad = 8,
  });

  final List<Widget> children;
  final double radius;
  final double hpad;
  final double vpad;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      radius: radius,
      hpad: hpad,
      vpad: vpad,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: children,
      ),
    );
  }
}

/// Einzelnes Icon im Navigationsbereich mit Hover-/Active-State.
class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.iconSize = 22,
    this.buttonHeight = 48,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double iconSize;
  final double buttonHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color fg = selected ? cs.secondary : cs.onSurface.withOpacity(0.97);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.6,
      onPressed: onTap,
      child: SizedBox(
        height: buttonHeight,
        child: Center(
          child: Icon(icon, color: fg, size: iconSize),
        ),
      ),
      minimumSize: Size(0, 0),
    );
  }
}

/* =============================================================================
   Widgets (kleine Hilfsklassen)
==============================================================================*/

/// Überschrift für Transfer-Schritte mit kleinerem Untertitel.
class _StepTitle extends StatelessWidget {
  const _StepTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    // KEIN const Text mehr, weil 'text' zur Laufzeit kommt.
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

/// Dialog, der Benutzername/Passwort abfragt und im Storage persistiert.
class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

/// Kümmert sich um Form-Validierung und Rückgabe der Login-Daten.
class _LoginDialogState extends State<_LoginDialog> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  String? _error;
  bool _busy = false;

  String _normUser(String s) => s.trim().toLowerCase().replaceAll(' ', '');

  Future<void> _onLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 200)); // kleine UX-Pause

    final ok = (_normUser(_u.text) == 'user1' && _p.text == '1234');
    if (ok) {
      await authStorage.setLoggedIn(
        _u.text.trim().isEmpty ? 'User 1' : _u.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(); // Dialog schließen
    } else {
      setState(() {
        _error = 'Falsche Zugangsdaten';
        _busy = false;
      });
    }
  }

  void _onCreate() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account-Erstellung kommt später')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.r.gutter,
          context.r.gutter,
          context.r.gutter,
          context.r.gutter,
        ),
        child: _GlassSurface(
          radius: 26,
          hpad: 18,
          vpad: 18,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Titel
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Anmelden',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        CupertinoIcons.xmark,
                        color: cs.onSurface.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: cs.outlineVariant),
                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bitte melde dich an oder erstelle einen Account.',
                    style: TextStyle(color: cs.onSurface.withOpacity(0.85)),
                  ),
                ),
                const SizedBox(height: 14),

                // Felder
                CupertinoTextField(
                  controller: _u,
                  placeholder: 'Benutzername (z.B. User 1)',
                  placeholderStyle: TextStyle(
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                  decoration: const BoxDecoration(color: Colors.transparent),
                  style: TextStyle(color: cs.onSurface),
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: _p,
                  placeholder: 'Passwort (1234)',
                  placeholderStyle: TextStyle(
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                  decoration: const BoxDecoration(color: Colors.transparent),
                  style: TextStyle(color: cs.onSurface),
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _onLogin(),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Divider(height: 1, color: cs.outlineVariant),
                const SizedBox(height: 12),

                // Buttons (rechtsbündig)
                Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      onPressed: _onCreate,
                      child: Text(
                        'Account erstellen',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      onPressed: _busy ? null : _onLogin,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CupertinoActivityIndicator(),
                            )
                          : Text(
                              'Anmelden',
                              style: TextStyle(
                                color: cs.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* =============================================================================
   Einstellungen (ThemeMode + Farben)
==============================================================================*/

/* =============================================================================
   Einstellungen & Hilfsdialoge
   -----------------------------------------------------------------------------
   Optionen für Theme-Anpassung, Login und First-Run-Hinweise. Ergänzt um
   wiederverwendbare Widgets wie PillLink und SectionHeader.
==============================================================================*/

/// Einstellungsseite für Farben, Dark/Light-Mode und Utility-Aktionen.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        context.r.gutter,
        80,
        context.r.gutter,
        context.r.bottomBarH + context.r.gutter,
      ),
      children: [
        Text(
          'Einstellungen',
          style: text.headlineLarge!.copyWith(height: 1.05),
        ),
        const SizedBox(height: 6),
        Divider(color: cs.outlineVariant, height: 1),

        const SizedBox(height: 18),
        const _SectionHeader('Hilfe'),

        const SizedBox(height: 8),
        PillLink(
          label: 'Tipps & Hilfen',
          onTap: () => _notImplemented(context, 'Tipps & Hilfen'),
        ),
        const SizedBox(height: 14),
        PillLink(
          label: 'Bedienungsanleitung',
          onTap: () => _notImplemented(context, 'Bedienungsanleitung'),
        ),
        const SizedBox(height: 14),
        PillLink(
          label: 'Parsertest',
          onTap: () => _openParserTest(context),
        ),

        const SizedBox(height: 26),
        Divider(color: cs.outlineVariant, height: 1),

        const SizedBox(height: 18),
        const _SectionHeader('Aussehen'),

        const SizedBox(height: 8),
        PillLink(
          label: 'Farbschema ändern',
          onTap: () => _openThemeMode(context),
        ),
        const SizedBox(height: 14),
        PillLink(
          label: 'Farben',
          compact: true,
          onTap: () => _openColors(context),
        ),

        const SizedBox(height: 26),
        Divider(color: cs.outlineVariant, height: 1),

        const SizedBox(height: 18),
        const _SectionHeader('Account'),

        const SizedBox(height: 8),
        PillLink(
          label: 'Persönliche Informationen',
          onTap: () => _notImplemented(context, 'Persönliche Informationen'),
        ),
        const SizedBox(height: 14),
        PillLink(
          label: 'Abmelden',
          compact: true,
          onTap: () => _notImplemented(context, 'Abmelden'),
        ),
      ],
    );
  }

  void _openThemeMode(BuildContext context) {
    final themeCtrl = ThemeProvider.of(context);
    final current = themeCtrl.mode;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) {
        ThemeMode sel = current;
        final cs = Theme.of(context).colorScheme;
        return Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              context.r.gutter,
              16,
              context.r.gutter,
              20,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(context.r.pillRadius()),
              ),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Farbschema',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Divider(color: cs.outlineVariant, height: 1),

                  const SizedBox(height: 16),
                  CupertinoSegmentedControl<ThemeMode>(
                    groupValue: sel,
                    children: const {
                      ThemeMode.light: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Hell'),
                      ),
                      ThemeMode.dark: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Dunkel'),
                      ),
                      ThemeMode.system: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('System'),
                      ),
                    },
                    onValueChanged: (m) => sel = m,
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Spacer(),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          context.r.pillRadius(true),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Abbrechen'),
                      ),
                      const SizedBox(width: 10),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        borderRadius: BorderRadius.circular(
                          context.r.pillRadius(true),
                        ),
                        onPressed: () {
                          themeCtrl.setThemeMode(sel);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Übernehmen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _notImplemented(BuildContext context, String where) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$where geöffnet (Stub)'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openParserTest(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ParserTestPage()),
    );
  }

  void _openColors(BuildContext context) {
    final themeCtrl = ThemeProvider.of(context);
    final textController = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) {
        return Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              context.r.gutter,
              16,
              context.r.gutter,
              20,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(context.r.pillRadius()),
              ),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Farben',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Divider(color: cs.outlineVariant, height: 1),

                  const SizedBox(height: 16),
                  Text(
                    'Schnell-Presets',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium!.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),

                  // Presets
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ColorChip(
                        color: const Color(0xFFD4AF37),
                        label: 'Gold',
                        onTap: () {
                          themeCtrl.applyPresetGold();
                          Navigator.pop(ctx);
                        },
                      ),
                      _ColorChip(
                        color: const Color(0xFF4EA2C9),
                        label: 'Blau',
                        onTap: () {
                          themeCtrl.applyPresetBlue();
                          Navigator.pop(ctx);
                        },
                      ),
                      _ColorChip(
                        color: const Color(0xFF65C94E),
                        label: 'Grün',
                        onTap: () {
                          themeCtrl.applyPresetGreen();
                          Navigator.pop(ctx);
                        },
                      ),
                      _ColorChip(
                        color: const Color(0xFFE15BA6),
                        label: 'Pink',
                        onTap: () {
                          themeCtrl.applyPresetPink();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  Divider(color: cs.outlineVariant, height: 1),
                  const SizedBox(height: 14),

                  Text(
                    'Eigene Farbe (HEX, z.B. D4AF37)',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium!.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: textController,
                          placeholder: 'HEX ohne #',
                          placeholderStyle: TextStyle(
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.transparent,
                          ),
                          style: TextStyle(color: cs.onSurface),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9a-fA-F]'),
                            ),
                            LengthLimitingTextInputFormatter(6),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          context.r.pillRadius(true),
                        ),
                        onPressed: () {
                          final hex = textController.text.trim();
                          if (hex.length == 6) {
                            final color = Color(int.parse('0xFF$hex'));
                            themeCtrl.setAccent(
                              color,
                            ); // persistiert automatisch
                            Navigator.pop(ctx);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bitte 6-stelligen HEX-Wert eingeben',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: const Text('Übernehmen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ein einzelnes Farbmuster zum schnellen Wechsel des Akzenttons.
class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.color,
    required this.label,
    required this.onTap,
  });
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.3), blurRadius: 10),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface)),
        ],
      ),
    );
  }
}

/// Überschrift-Widget mit optionaler Action-Schaltfläche.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium!.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    );
  }
}

/// Klickbare „Pill“-Schaltfläche mit Chevron – wirkt wie ein Link, reagiert
/// aber auf Tap wie ein Button.
class PillLink extends StatelessWidget {
  const PillLink({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final basePadV = compact ? 10.0 : 14.0;
    final basePadH = compact ? 16.0 : 20.0;
    final radius = context.r.pillRadius(compact);
    final cs = Theme.of(context).colorScheme;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: basePadH, vertical: basePadV),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '>',
              style: TextStyle(
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== FIRST RUN FULLSCREEN ====================

/* =============================================================================
   Onboarding & First-Run Flows
   -----------------------------------------------------------------------------
   Kombiniert den simplen FirstRunScreen, die mehrstufige Onboarding-Sequenz
   sowie CustomPainter-basierte Illustrationen.
==============================================================================*/

/// Einfacher Screen, der nach dem ersten App-Start erklärt was zu tun ist.
class FirstRunScreen extends StatelessWidget {
  const FirstRunScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async => false, // Zurück-Geste blocken
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final h = c.maxHeight;

              return Stack(
                children: [
                  // Hintergrund: Berge + Straße
                  Positioned.fill(
                    child: CustomPaint(painter: _OnboardingScenePainter()),
                  ),

                  // Header-Pill links oben („Anmelden“)
                  Positioned(left: 20, top: 12, child: _chip('Anmelden', cs)),

                  // Logo zentriert oben (quadratisch wie im Shot)
                  Positioned(
                    top: h * 0.13,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: w * 0.48,
                        height: w * 0.48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF30343A),
                            width: 8,
                          ),
                          boxShadow: const [
                            BoxShadow(blurRadius: 18, color: Colors.black54),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '[K]',
                            style: TextStyle(
                              fontSize: w * 0.22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2F3439),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Buttons unten auf der Straße
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 28 + MediaQuery.of(context).padding.bottom,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _pillButton(
                          label: 'Anmelden',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 14),
                        _pillButton(
                          label: 'Account erstellen',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 10),
                        _skipButton(
                          label: 'überspringen',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2E),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _pillButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        color: const Color(0xFF2A2A2E),
        borderRadius: BorderRadius.circular(28),
        onPressed: onTap, // echte Logik später
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _skipButton({required String label, required VoidCallback onTap}) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E20),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      minimumSize: Size(0, 0),
    );
  }
}

// ------------- Szene (Berge + Straße) wie im Screenshot ----------------
/// Malt die Intro-Illustration (Straße, Himmel, LKW etc.).
class _OnboardingScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = const Color(0xFF0F1012);
    final mountain = const Color(0xFF3C3A42);
    final mountainDark = const Color(0xFF2E2C33);
    final road = const Color(0xFF3B3C3E);
    final stripe = Colors.white.withOpacity(0.85);

    // BG
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    // Berge
    final h = size.height;
    final w = size.width;

    Path m1 = Path()
      ..moveTo(0, h * 0.42)
      ..lineTo(w * 0.32, h * 0.27)
      ..lineTo(w * 0.64, h * 0.42)
      ..lineTo(0, h * 0.58)
      ..close();
    canvas.drawPath(m1, Paint()..color = mountainDark);

    Path m2 = Path()
      ..moveTo(w * 0.36, h * 0.46)
      ..lineTo(w * 0.70, h * 0.30)
      ..lineTo(w, h * 0.54)
      ..lineTo(w, h * 0.64)
      ..close();
    canvas.drawPath(m2, Paint()..color = mountain);

    // Straße (Trapez)
    final roadTop = h * 0.46;
    final path = Path()
      ..moveTo(w * 0.40, roadTop)
      ..lineTo(w * 0.60, roadTop)
      ..lineTo(w * 0.82, h)
      ..lineTo(w * 0.18, h)
      ..close();
    canvas.drawPath(path, Paint()..color = road);

    // Mittelstreifen (gestrichelt)
    final p1 = Offset(w * 0.50, roadTop + 8);
    final p2 = Offset(w * 0.50, h - 16);
    final total = (p2.dy - p1.dy);
    const seg = 26.0;
    const gap = 16.0;
    double y = p1.dy;
    final paintStripe = Paint()
      ..color = stripe
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.square;
    while (y < p2.dy) {
      final y2 = (y + seg).clamp(0, p2.dy).toDouble();

      canvas.drawLine(Offset(w * 0.50, y), Offset(w * 0.50, y2), paintStripe);
      y += seg + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// === ONBOARDING (Vollbild) ================================================
/// Vollbild-Onboarding mit Schrittindikator, Buttons und Animationen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// State-Objekt verwaltet PageView, Animationen und Persistenz-Flags.
class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // beide Bilder vorladen (deine bestehenden Assets)
    for (final p in const [
      'assets/images/backgroundlight.png',
      'assets/images/backgrounddark.png',
    ]) {
      precacheImage(AssetImage(p), context).catchError((_) {});
    }
  }

  void _openLogin(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _LoginDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgAsset = isDark
        ? 'assets/images/backgrounddark.png'
        : 'assets/images/backgroundlight.png';

    final w = MediaQuery.of(context).size.width;
    final btnWidth = (w * 0.72).clamp(260, 340).toDouble();
    const btnRadius = 28.0;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Hintergrundbild, am unteren Rand ausgerichtet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Image.asset(bgAsset, fit: BoxFit.cover),
          ),

          // Inhaltsebene
          SafeArea(
            child: Stack(
              children: [
                // ── 1) Oben links: "Anmelden"-Chip (unverändert, nur als Label)
                Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 20, top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      'Anmelden',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                // ── 2) Hauptsäule: Logo + Buttons (Buttons ein Stück höher)
                Column(
                  children: [
                    const Spacer(flex: 1),

                    // Logo
                    Container(
                      width: w * 0.45,
                      height: w * 0.45,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFF44464A),
                          width: 8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 20,
                            color: Colors.black.withOpacity(
                              isDark ? 0.55 : 0.18,
                            ),
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '[K]',
                          style: TextStyle(
                            fontSize: w * 0.22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2F3439),
                          ),
                        ),
                      ),
                    ),

                    // << dieser Spacer steuert, wie weit die Buttons nach oben rücken
                    const Spacer(flex: 1),

                    // Buttons (kleiner Abstand dazwischen)
                    _OnbButton(
                      width: btnWidth,
                      radius: btnRadius,
                      label: 'Anmelden',
                      onTap: () => _openLogin(context),
                    ),
                    const SizedBox(height: 20), // kleiner freier Bereich
                    _OnbButton(
                      width: btnWidth,
                      radius: btnRadius,
                      label: 'Account erstellen',
                      onTap: () => _openLogin(context),
                    ),

                    // kleinerer Spacer unten, damit die Buttons höher stehen
                    const Spacer(flex: 1),
                  ],
                ),

                // ── 3) "überspringen" fest an den unteren Bildschirmrand
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withOpacity(0.25)
                                  : Colors.black.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text(
                              'überspringen',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Einheitlicher Button-Stil für das Onboarding (Primär/Sekundär).
class _OnbButton extends StatelessWidget {
  const _OnbButton({
    required this.width,
    required this.radius,
    required this.label,
    required this.onTap,
  });

  final double width;
  final double radius;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Light: hellgrau + dunkler Text, Dark: dunkel + weißer Text
    final bg = cs.surfaceContainerHighest;
    final fg = cs.onSurface;

    return Center(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Raster-Element mit Logo/Partneranzeige im Onboarding.
class _LogoTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final double size = (w * 0.48).clamp(180, 280);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF374149), width: 10),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 30, spreadRadius: 6),
        ],
      ),
      child: Center(
        child: Text(
          '[K]',
          style: TextStyle(
            color: const Color(0xFF374149),
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

/// Zeichnet Berge + Straße + gestrichelte Mittelspur.
/// Speziell so aufgebaut wie deine Figma-Formen (Dreiecke/Trapez).
/// Zeichenlogik für die Straße inkl. Streifen & perspektivischem Verlauf.
class _RoadScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Farben (aus dem Mock)
    const bg = Color(0xFF0F0F11);
    const mountainDark = Color(0xFF2E2D33);
    const mountainMid = Color(0xFF3E3C45);
    const road = Color(0xFF3C3C3F);
    const stripe = Color(0xFFE6E6E6);

    // Grund
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    // Berg-Layer unten (breite Trapeze/Dreiecke)
    final p = Path();

    // linker breiter Hügel
    p.reset();
    p.moveTo(-w * 0.10, h * 0.52);
    p.lineTo(w * 0.32, h * 0.35);
    p.lineTo(w * 0.58, h * 0.52);
    p.lineTo(-w * 0.10, h * 0.80);
    p.close();
    canvas.drawPath(p, Paint()..color = mountainMid);

    // rechter breiter Hügel
    p.reset();
    p.moveTo(w * 1.10, h * 0.54);
    p.lineTo(w * 0.62, h * 0.40);
    p.lineTo(w * 0.40, h * 0.55);
    p.lineTo(w * 1.10, h * 0.86);
    p.close();
    canvas.drawPath(p, Paint()..color = mountainMid);

    // Pfeil / Bergspitze mittig hinten
    p.reset();
    p.moveTo(w * 0.18, h * 0.58);
    p.lineTo(w * 0.50, h * 0.38);
    p.lineTo(w * 0.82, h * 0.58);
    p.lineTo(w * 0.50, h * 0.52);
    p.close();
    canvas.drawPath(p, Paint()..color = mountainDark.withOpacity(0.95));

    // Straße (Trapez, verjüngt)
    p.reset();
    p.moveTo(w * 0.20, h * 0.98);
    p.lineTo(w * 0.33, h * 0.58);
    p.lineTo(w * 0.67, h * 0.58);
    p.lineTo(w * 0.80, h * 0.98);
    p.close();
    canvas.drawPath(p, Paint()..color = road);

    // Straßen-Mittelstreifen (gestrichelt)
    final paintStripe = Paint()
      ..color = stripe
      ..style = PaintingStyle.fill;

    final double topY = h * 0.60;
    final double bottomY = h * 0.97;
    final double dashH = (h * 0.035).clamp(14.0, 26.0);
    final double gapH = dashH * 0.80;
    double y = topY;

    while (y < bottomY - dashH) {
      // Trapezförmig leicht schmaler nach oben
      final t = ((y - topY) / (bottomY - topY)).clamp(0.0, 1.0);
      final halfW = lerpDouble(3.6, 6.0, t)!; // perspektivisch minimal breiter
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.50, y + dashH / 2),
          width: halfW * 2,
          height: dashH,
        ),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(rect, paintStripe);
      y += dashH + gapH;
    }

    // dünne Randstreifen der Straße (ganz dezent)
    final edgePaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final edge = Path()
      ..moveTo(w * 0.33, h * 0.58)
      ..lineTo(w * 0.20, h * 0.98)
      ..moveTo(w * 0.67, h * 0.58)
      ..lineTo(w * 0.80, h * 0.98);
    canvas.drawPath(edge, edgePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
