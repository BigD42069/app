# Android native library drop-in

Place the prebuilt `mobile.aar` produced by the gomobile pipeline in this folder before building.

The Gradle build is configured to load `mobile.aar` from `libs/` via `implementation(files("libs/mobile.aar"))`.
This artifact is intentionally gitignored — keep it out of commits by copying it locally when you need to build.
