# Flutter-Plugin-Brücke (MethodChannel)

Dieser Leitfaden definiert den MethodChannel-Kontrakt zwischen Flutter und den
`gomobile`-Artefakten. Er beschreibt Parameter, Rückgabewerte sowie das
Threading- und Abbruchverhalten.

## Channel & Methoden

- **Channel-Name:** `tachograph_native`
- **Methode:** `parseDdd`

### Parameter

| Schlüssel        | Typ            | Beschreibung |
| ---------------- | -------------- | ------------ |
| `payload`        | `Uint8List`    | DDD-Datei als Bytestrom |
| `source`         | `String`       | "vu" (Fahrzeuggerät) oder "card" |
| `verify`         | `bool`         | Signaturprüfung aktivieren |
| `pksPath`        | `String`       | Absoluter Pfad zum PKS-Verzeichnis |
| `timeoutMs`      | `int?`         | Optionales Timeout (Millisekunden); die Dart-Seite sendet standardmäßig 30.000 |

### Rückgabe

Die native Seite liefert eine Map mit folgenden Schlüsseln:

| Schlüssel            | Typ        | Beschreibung |
| -------------------- | ---------- | ------------ |
| `status`             | `String`   | `ok`, `error` oder `cancelled` |
| `json`               | `String?`  | Serialisierte Payload bei Erfolg |
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
- Zusätzlich kann Flutter `cancelActiveParse` aufrufen. Der native Code stoppt
  daraufhin laufende Jobs (z. B. via Kontext-Abbruch).
- Der Cancel-Pfad propagiert den Status `cancelled` zurück.

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

### JSON-Payload

Bei erfolgreicher Analyse enthält das `json`-Feld eine Struktur mit folgenden
Schlüsseln:

| Schlüssel      | Typ            | Beschreibung |
| -------------- | -------------- | ------------ |
| `bytes`        | `int`          | Länge der DDD-Datei |
| `source`       | `String`       | Übernommener `source`-Parameter |
| `sha256`       | `String`       | Prüfsumme der Rohdatei |
| `generatedAt`  | `String`       | ISO-Zeitstempel der Generierung |
| `totalDays`    | `int`          | Anzahl der extrahierten Tage |
| `days`         | `List<Object>` | Liste einzelner Tage |

Jedes Element in `days` besitzt die Schlüssel `date` (`YYYY-MM-DD`),
`startOdometer`, `endOdometer` sowie `distanceKm`. Die Logik entspricht der
bisherigen Dart-Implementierung und berücksichtigt 24-Bit-Überläufe des
Kilometerzählers.

Der „Done“-Zustand ist erreicht, wenn die oben genannten Signaturen stabil sind
und die nativen Implementierungen alle Pfade bedienen.
