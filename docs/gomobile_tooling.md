# Gomobile Toolchain & Artefact Guidelines

Dieser Leitfaden beschreibt den Build-Prozess für die nativen Bibliotheken, die
über `gomobile` erzeugt werden. Er deckt sowohl Android (AAR) als auch iOS
(`.xcframework`) Ziele ab und dokumentiert die dafür benötigte Toolchain.

## Tooling & Zielplattformen

| Komponente | Version/Anforderung | Zweck |
| --- | --- | --- |
| Go | >= 1.22 | Basis für `gomobile` und Go-Code |
| gomobile | >= 0.0.0-20240509 | Bindings-Erzeugung |
| Java Development Kit | Temurin 17 | Android Gradle Build |
| Android SDK | API Level 34+, Build-Tools 34.0.0 | AAR-Compilation |
| Android NDK | r26d | Native Kompilierung |
| Xcode | 15.4+ | iOS/macOS Builds |

Die generierten Artefakte müssen folgende ABIs/Targets enthalten:

- **Android**: `arm64-v8a` und `x86_64` in einer AAR-Datei
- **iOS**: Ein `.xcframework` mit `ios-arm64` (Device) und `ios-arm64_x86_64-simulator`

### Installation validieren

Die Toolchain ist „Done“, wenn folgende Checks erfolgreich laufen:

```bash
go version
gomobile version
sdkmanager --list | grep "platforms;android-34"
sdkmanager --list | grep "build-tools;34.0.0"
sdkmanager --list | grep "ndk;26.1.10909125"
/usr/libexec/java_home -v 17
xcode-select -p
xcodebuild -version
```

> Hinweis zur CI-/Container-Umgebung: Der Standard-Go-Modul-Proxy ist dort
> nicht erreichbar. Installieren Sie `gomobile` und weitere Abhängigkeiten
> deshalb lokal mit aktivem Internetzugang (z. B. `go install` auf Ihrem
> Entwicklungsrechner) oder stellen Sie einen internen Proxy bereit. Anschließend
> kann das Build-Skript mit den lokal installierten Tools ausgeführt werden.

## Build-Skript verwenden

Das Skript [`tool/build_gomobile.sh`](../tool/build_gomobile.sh) kapselt die
Build-Schritte. Es setzt das Environment `GOMOBILE_BIND_PACKAGE`, das auf das
Go-Paket mit den Exporten zeigt.

```bash
export GOMOBILE_BIND_PACKAGE=github.com/company/tachograph/mobile
./tool/build_gomobile.sh 1.2.0
```

Standardmäßig landen die Artefakte in `build/gomobile/<VERSION>/`:

```
build/gomobile/1.2.0/android/tachograph-1.2.0.aar
build/gomobile/1.2.0/apple/Tachograph.xcframework
build/gomobile/1.2.0/checksums.txt
```

> Hinweis: Binäre Artefakte werden **nicht** im Git-Repository versioniert. Die
> Ausgabeordner sind nur dokumentiert, damit lokale Builds konsistent
> strukturiert werden können.

### Manuelle Ausführung

Der Workflow, den das Skript automatisiert, lautet:

```bash
# Android
GOMOBILE_BIND_PACKAGE=github.com/company/tachograph/mobile \
  gomobile bind \
    -target=android/arm64,android/amd64 \
    -androidapi 24 \
    -o build/gomobile/1.2.0/android/tachograph-1.2.0.aar \
    "$GOMOBILE_BIND_PACKAGE"

# iOS
GOMOBILE_BIND_PACKAGE=github.com/company/tachograph/mobile \
  gomobile bind \
    -target=ios,iossimulator \
    -o build/gomobile/1.2.0/apple/Tachograph.xcframework \
    "$GOMOBILE_BIND_PACKAGE"
```

> Hinweis: Für das iOS-Build muss vorher `gomobile init` ausgeführt werden, damit
die iOS-Toolchain korrekt heruntergeladen wird.

## API-Verifikation

Vor dem Tagging der Artefakte wird sichergestellt, dass die exportierte API dem
Wrapper-Kontrakt entspricht:

1. `gomobile bind` erzeugt automatisch Header (`*.h`) und Stubs (`*.swift`).
2. Diese Dateien werden gegen die erwarteten Signaturen diff-vergleich (siehe
   `docs/flutter_plugin_bridge.md`).
3. Ein automatischer Check (z. B. `go test ./mobile/...`) wird ausgeführt, um
   Kompatibilität sicherzustellen.

## Versionierung

- Artefakte werden mit `v<SEMVER>` getaggt und im Artefakt-Repository abgelegt.
- Zusätzlich wird ein `checksums.txt` mit SHA256-Hashes erzeugt.
- Der Commit, der die Bindings erzeugt, referenziert genau diese Tag-Version.

Damit ist der "Done"-Zustand erreicht, sobald AAR & XCFramework in der
Artefakt-Ablage liegen und mit dem gleichen SemVer-Tag versehen sind.
