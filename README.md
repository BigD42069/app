# dateiexplorer_tachograph

A new Flutter project.

## Mobile Native Pipeline

Details zur gomobile-Toolchain und zum Flutter-Plugin-Kontrakt sind in den
folgenden Dokumenten zusammengefasst:

- [`docs/gomobile_tooling.md`](docs/gomobile_tooling.md)
- [`docs/flutter_plugin_bridge.md`](docs/flutter_plugin_bridge.md)

## Aktueller Integrationsstatus

- Der Go-basierte Tachograph-Parser liegt unter [`mobile/`](mobile/) und kann
  via `go test ./mobile` lokal geprüft werden.
- Damit Flutter (Android/iOS) den Parser nutzen kann, müssen zuerst die
  gomobile-Bindings (AAR & `.xcframework`) erzeugt und in die jeweiligen
  Projekte eingebunden werden. Das Skript [`tool/build_gomobile.sh`](tool/build_gomobile.sh)
  beschreibt den erwarteten Build-Prozess.
- Solange die Artefakte fehlen, liefert der Flutter-Plugin-Stub eine
  `PlatformException` mit dem Fehlercode `missing-native-lib`.

> Hinweis: In der bereitgestellten Container-Umgebung ist kein Zugriff auf den
> öffentlichen Go-Modul-Proxy möglich. Installieren Sie `gomobile` daher in
> Ihrer lokalen Entwicklungsumgebung (z. B. via `go install` mit aktivem
> Netzwerkzugang) und führen Sie den Build dort aus.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
