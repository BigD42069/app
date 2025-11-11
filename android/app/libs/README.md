# Android native library drop-in

Place the prebuilt `android.lib.aar` produced by the gomobile pipeline in this folder before building.

The Gradle build is configured to load `android.lib.aar` from `libs/` via `implementation(files("libs/android.lib.aar"))`.
This artefact is intentionally gitignored — keep it out of commits by copying it locally when you need to build.
