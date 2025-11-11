# iOS native framework drop-in

Place the generated `Mobile.xcframework` directory from the gomobile build output inside this folder before running Xcode.

The Xcode project links and embeds `ios/Frameworks/Mobile.xcframework` (relative to the repository root).
Keep the architecture slices intact (`ios-arm64/Mobile.framework` for devices,
`ios-arm64_x86_64-simulator/Mobile.framework` for the simulator); Xcode selects
the appropriate variant automatically and needs the bundled headers
(`Mobile.h`, `Mobile.objc.h`).
The framework directory is gitignored on purpose — copy it locally for builds instead of committing it to the repository.
