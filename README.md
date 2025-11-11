# dateiexplorer_tachograph

A new Flutter project.

## Mobile Native Pipeline

Details zur gomobile-Toolchain und zum Flutter-Plugin-Kontrakt sind in den
folgenden Dokumenten zusammengefasst:

- [`docs/gomobile_tooling.md`](docs/gomobile_tooling.md)
- [`docs/flutter_plugin_bridge.md`](docs/flutter_plugin_bridge.md)

## Native gomobile-Artefakte einbinden

Die von der gomobile-Toolchain erzeugten Binärartefakte müssen an die vom
Projekt erwarteten Stellen kopiert werden, damit sie von Gradle bzw. Xcode
gefunden und eingebunden werden:

| Plattform | Erwarteter Pfad | Hinweise |
|-----------|-----------------|----------|
| Android   | `android/app/libs/android.lib.aar` | Die `android/app/build.gradle.kts` lädt das AAR direkt aus diesem Verzeichnis via `implementation(files("libs/androidlib.aar"))`. Du musst die Datei genau so benennen und lokal einspielen. |
| iOS       | `ios/Frameworks/ios.xcframework` | Das Xcode-Projekt referenziert das Framework relativ zum `Frameworks/`-Ordner (`path = ../Frameworks/ios.xcframework`). Kopiere den kompletten `ios.xcframework`-Ordner dort hinein, bevor du Xcode startest. |

Die beiden Ordner sind per `.gitignore` von Commits ausgeschlossen, damit keine großen Binärdateien im Repository landen. Lege die Artefakte deshalb nur lokal ab oder verwende ein separates Artefakt-Repository.

Weitere Details zum Build-Pipeline-Kontrakt findest du in den Dokumenten unter
[`docs/`](docs/).
