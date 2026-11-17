#!/usr/bin/env bash
# The gate /ship-then-land runs before anything is pushed.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

# Flutter isn't on PATH here; the SDK path Gradle uses is in the (gitignored) local.properties.
SDK=$(sed -n 's/^flutter\.sdk=//p' android/local.properties 2>/dev/null || true)
[ -n "$SDK" ] && export PATH="$SDK/bin:$PATH"

flutter pub get >/dev/null
# Mocks and migration schemas are generated, not committed; the tests can't load without them.
dart run build_runner build --delete-conflicting-outputs >/dev/null
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/ >/dev/null
flutter analyze --no-fatal-infos
flutter test
