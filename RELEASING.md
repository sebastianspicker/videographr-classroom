# Releasing

This procedure publishes a source-only GitHub prerelease. It does not produce a
signed IPA, a TestFlight build, an App Store submission, or authorization to
collect classroom or minor data.

## Prepare and validate a candidate

1. Set `RELEASE_VERSION` and align the Xcode marketing version and build number.
2. Update `CHANGELOG.md` and the matching file in
   `docs/releases/`.
3. Review the full candidate surface for media, exports, credentials, signing
   material, environment files, local tool state, and build output.
4. Run the full gate on the exact candidate commit:

```bash
bash scripts/verify_release.sh
git status --short --untracked-files=all
git diff HEAD --check
```

This file is the single description of the gate; other documents link here.
`scripts/verify_release.sh` runs, in order:

1. `scripts/verify_architecture.py`: SwiftPM dependency direction, no
   experimental code in `GuidanceEngine`, no `FileManager` in
   `SessionCore/Domain`, app code outside `Application/` reaching persistence only
   through `AppStore`, and every app Swift file referenced in the Xcode project.
2. `scripts/verify_public_hygiene.py` and `scripts/verify_demo.py`.
3. Shell syntax (plus ShellCheck when installed) and `plutil` lint of the
   Info.plist and Xcode project.
4. A Release Swift build with complete concurrency checking and warnings as
   errors.
5. Hardware-free Xcode app-unit tests on an iPhone Simulator, then
   signing-disabled Xcode Release Simulator analysis and build.
   If the app-unit tests fail, the gate prints the test-result summary from
   their Xcode result bundle before exiting with the test step's status.

The app-unit tests cover capture-event generation filtering, exact transaction
filtering, idempotent stop emission, autosave ordering, bootstrap and import
failures, persisted provenance strings, and first-attachment playback routing in a
hosted SwiftUI view. There is no separate UI-test target, screenshot-baseline
harness, physical-device validation, or scientific validation.

The optional Gaussian perspective checks are not part of the gate. Run them
manually when that feature changes:
`python3 scripts/verify_gaussian_splats.py --require-model --require-metal`
(see [Gaussian perspective](docs/GAUSSIAN_SPLATS.md)).

## Review, tag, and publish

After explicit maintainer approval, review the exact staged file list, then
commit. Push only after a separate approval, and wait for required CI on that
immutable commit. Do not change release metadata between successful CI and
tagging.

Before publication, verify remote branch protection, required checks, repository
visibility, rendered community-file links, private vulnerability reporting, and a
separate monitored conduct-reporting route. These are external states that a
local checkout cannot confirm.

```bash
VERSION="$(tr -d '[:space:]' < RELEASE_VERSION)"
git rev-parse HEAD
git tag -s "v${VERSION}" -m "Videographr ${VERSION}"
git show --stat "v${VERSION}"
git push origin "v${VERSION}"
gh release create "v${VERSION}" \
  --prerelease \
  --title "Videographr ${VERSION}" \
  --notes-file "docs/releases/${VERSION}.md" \
  --verify-tag
```

Use an annotated unsigned tag only when signing is unavailable and you have
recorded the exception. Never move or recreate a published tag, and never attach
a binary without a separate signing, privacy, device-validation, and distribution
process.

## Rollback

Before publication, correct the candidate and rerun the gate. After publication,
mark the faulty prerelease superseded and release a new version. Do not rewrite
the published tag.
