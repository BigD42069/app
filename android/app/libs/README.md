# Android native library drop-in

Place the prebuilt `android.lib.aar` produced by the gomobile pipeline in this folder.

The Gradle build is configured to load `android.lib.aar` from `libs/` via `implementation(files("libs/android.lib.aar"))`.
