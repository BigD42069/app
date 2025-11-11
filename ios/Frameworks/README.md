# iOS native framework drop-in

Historically, the gomobile output was dropped into this directory, aber aktuell
erwartet das Xcode-Projekt den Ordner `ios.xcframework` **direkt im Verzeichnis
`ios/`**.

Kopiere daher den erzeugten `ios.xcframework`-Ordner auf dieselbe Ebene wie
`Runner.xcodeproj`. Dieses README bleibt nur als Hinweis erhalten, dass die
Frameworks nicht eingecheckt werden.
Keep the architecture slices intact (`ios-arm64/Mobile.framework` for devices,
`ios-arm64_x86_64-simulator/Mobile.framework` for the simulator); Xcode selects
the appropriate variant automatically and needs the bundled headers
(`Mobile.h`, `Mobile.objc.h`).
The framework directory is gitignored on purpose — copy it locally for builds instead of committing it to the repository.
