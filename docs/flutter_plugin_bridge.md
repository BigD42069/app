# Flutter-Plugin-Brücke (MethodChannel)

Dieser Leitfaden definiert den MethodChannel-Kontrakt zwischen Flutter und den
`gomobile`-Artefakten. Er beschreibt Parameter, Rückgabewerte sowie das
Threading- und Abbruchverhalten.

## Plattform-spezifische Implementierung

- **Android (`android/app/src/...`)** bindet die Datei
  `android/app/libs/mobile.aar`. Der Kotlin-Plugin-Code
  (`TachographNativePlugin.kt`) instanziiert den Parser via
  `mobile.Mobile.createParser(...)` und ruft `parseCard`, `parseVehicleUnit`
  oder `parseWithTimeout` auf.
- **iOS (`ios/Runner/...`)** verlinkt `ios/Frameworks/Mobile.xcframework`. Die
  Swift-Implementierung importiert das Framework (Modul `Mobile`) und ruft
  `MobileCreateParser(...)` sowie `parseCard`/`parseVehicleUnit`/`parseWithTimeout` auf.

Beide Plattformen liefern somit den gleichen Kanal-Contract, greifen aber auf
ihre jeweilige native Bibliothek zurück.

## Channel & Methoden

- **Channel-Name:** `tachograph_native`
- **Methode:** `parseDdd`

### Parameter

| Schlüssel        | Typ            | Beschreibung |
| ---------------- | -------------- | ------------ |
| `payload`        | `Uint8List`    | DDD-Datei als Bytestrom |
| `source`         | `String`       | "vu" (Fahrzeuggerät) oder "card" |
| `pks1Dir`        | `String`       | Optional: Absoluter Pfad zu den Zertifikaten der ersten Generation |
| `pks2Dir`        | `String`       | Optional: Absoluter Pfad zu den Zertifikaten der zweiten Generation |
| `strictMode`     | `bool`         | Der gomobile-Parser ignoriert diesen Wert aktuell |
| `timeoutMs`      | `int?`         | Optionales Timeout (Millisekunden); `0` oder `<0` bedeutet kein Timeout |

### Rückgabe

Die native Seite liefert eine Map mit folgenden Schlüsseln:

| Schlüssel            | Typ        | Beschreibung |
| -------------------- | ---------- | ------------ |
| `status`             | `String`   | `ok` (Fehler kommen als PlatformException) |
| `json`               | `String?`  | Serialisierte Payload bei Erfolg |
| `verified`           | `bool`     | Ergebnis der Signaturprüfung |
| `verificationLog`    | `String?`  | Detaillog der Prüfschritte |
| `errorDetails`       | `String?`  | Fehlermeldung bei `error` |

## Threading-Vorgaben

- Der Aufruf erfolgt asynchron über den `MethodChannel` und blockiert damit
  nicht den UI-Thread. Die eigentliche Arbeit findet auf der nativen Seite
  statt.
- Längere Operationen müssen vom nativen Code in Worker-Threads ausgeführt
  werden.

## Abbruch/Timeout

- Flutter löst ein Timeout aus, indem `timeoutMs` gesetzt wird.
- `cancelActiveParse` ist derzeit ein No-op, weil die Mobile-API keinen Cancel
  anbietet.

## Fehlerbehandlung

- Alle Fehler werden als `PlatformException` mit Codes `parser-error`,
  `timeout`, `cancelled` oder `invalid-arguments` gemeldet.
- Die Dart-Seite wandelt diese Codes in strukturierte Exceptions um und blendet
  Nutzerfreundliche Meldungen ein.

## Tests

- Die Plugin-Methode wird in einem Integrationstest mit Sample-DDD-Dateien
  aufgerufen.
- Zusätzlich simulieren Mocks (`MethodChannel.setMockMethodCallHandler`) den
  Cancel-Pfad.

Der „Done“-Zustand ist erreicht, wenn die oben genannten Signaturen stabil sind
und die nativen Implementierungen alle Pfade bedienen.
