# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the Dart API surface for the plugin, including the public entrypoint, platform interface, method-channel implementation, and data models under `lib/bean/`. Native code lives in `android/src/main/kotlin/com/pdf/ad/flutter_pdf_ad_plugins/` and `ios/Classes/`. The demo app is in `example/`, with its Flutter UI in `example/lib/` and widget tests in `example/test/`. Android-specific unit tests for the plugin live in `android/src/test/`.

## Build, Test, and Development Commands
Run `flutter pub get` at the repository root to install plugin dependencies. Use `flutter analyze` to apply the `flutter_lints` rules from `analysis_options.yaml`. Launch the sample app with `cd example && flutter run` to verify plugin behavior end to end. Run Dart-side tests with `cd example && flutter test`. Run Android native unit tests with `cd example/android && ./gradlew testDebugUnitTest`.

## Coding Style & Naming Conventions
Follow standard Flutter style: 2-space indentation, trailing commas where they improve formatting, and concise doc comments on public APIs. Use `UpperCamelCase` for classes, `lowerCamelCase` for methods and fields, and `snake_case.dart` for file names. Keep channel and package identifiers stable unless a breaking change is intended; current values include `flutter_pdf_ad_plugins` and `com.pdf.ad.flutter_pdf_ad_plugins`. Format Dart code with `dart format lib example`.

## Testing Guidelines
Add or update tests with every behavior change. Place Flutter widget or integration-facing tests under `example/test/` and name them `*_test.dart`. Keep Android JVM tests beside the plugin under `android/src/test/.../*Test.kt`. Prefer assertions that cover visible behavior, method-channel results, and platform-specific edge cases.

## Commit & Pull Request Guidelines
The current Git history is minimal and does not establish a reliable convention beyond very short subjects. Use clear, imperative commit messages instead, for example `feat: add AdMob initialization API` or `fix: guard null platform channel result`. PRs should summarize the user-visible change, list the commands run for verification, and note any Android/iOS configuration impact. Include screenshots only when the `example/` UI changes.

## Security & Configuration Tips
Do not commit SDK paths, signing material, or ad network secrets. Treat `example/android/local.properties` and any future AdMob IDs or test credentials as local configuration, not shared source.
