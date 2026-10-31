#!/usr/bin/env bash
# Deterministic local/CI gate for the public source alpha candidate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Architecture boundaries"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify_architecture.py

echo "==> Public repository hygiene"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify_public_hygiene.py

echo "==> Static Pages demo"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify_demo.py

echo "==> Model download bounds"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.test_prepare_gaussian_model

echo "==> Script syntax"
bash -n scripts/*.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
fi
echo "==> Plist and Xcode project syntax"
plutil -lint App/Unterrichtsvideographie/Info.plist
plutil -lint App/Unterrichtsvideographie.xcodeproj/project.pbxproj

echo "==> Release Swift build"
swift build --disable-sandbox -c release \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors

echo "==> App unit tests"
SIMULATOR_ID="$(PYTHONDONTWRITEBYTECODE=1 python3 scripts/select_simulator.py)"
echo "Using iPhone simulator ${SIMULATOR_ID}"
RESULT_BUNDLE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/videographr-app-tests.XXXXXX")"
RESULT_BUNDLE="${RESULT_BUNDLE_DIR}/AppUnitTests.xcresult"
# Keep XCTest case output visible so intermittent CI failures identify the failing test.
app_test_status=0
xcodebuild \
  -project App/Unterrichtsvideographie.xcodeproj \
  -scheme Unterrichtsvideographie \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -resultBundlePath "${RESULT_BUNDLE}" \
  CODE_SIGNING_ALLOWED=NO \
  test || app_test_status=$?
if [ "${app_test_status}" -ne 0 ]; then
  # Log-only evidence; a CI artifact upload of RESULT_BUNDLE can replace this later.
  echo "App unit tests failed (exit ${app_test_status}). Result bundle: ${RESULT_BUNDLE}" >&2
  xcrun xcresulttool get test-results summary --path "${RESULT_BUNDLE}" >&2 \
    || echo "No test-result summary could be read from the result bundle." >&2
  exit "${app_test_status}"
fi
rm -rf -- "${RESULT_BUNDLE_DIR}"

echo "==> Xcode Release analysis"
xcodebuild -quiet \
  -project App/Unterrichtsvideographie.xcodeproj \
  -scheme Unterrichtsvideographie \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  clean analyze

echo "==> App build"
xcodebuild -quiet \
  -project App/Unterrichtsvideographie.xcodeproj \
  -scheme Unterrichtsvideographie \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Public alpha release gate passed."
