# iOS native framework drop-in

Place the generated `ios.xcframework` directory from the gomobile build output inside this folder before running Xcode.

The Xcode project links and embeds `Frameworks/ios.xcframework` (relative path `../Frameworks/ios.xcframework`).
The framework directory is gitignored on purpose — copy it locally for builds instead of committing it to the repository.
