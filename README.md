# Videographr

Videographr is a local-first iOS and iPadOS app for preparing, recording, and
reviewing classroom video. It records session context and scoped consent, captures
one continuous local take, stores time-linked reflection notes, and exports a
consent-scoped study package.

This repository contains the source for `v0.1.0-alpha.1`. It does not include a
signed application, TestFlight build, App Store package, backend, or cloud service.

Explore the [static interactive demo](https://sebastianspicker.github.io/videographr-classroom/)
with synthetic fixture data. It demonstrates the current five-tab workflow but
does not access a camera or microphone, read files, persist data, or create exports.

## Purpose and scope

The app supports a capture-to-review workflow for educational research and teacher
education. It reports direct technical observations about capture conditions. It
does not rate teaching, infer learning outcomes, or validate pedagogical constructs.

The source alpha is intended for contributors and methods evaluators using synthetic
material or recordings of consenting adults under an applicable protocol. The
repository does not authorize the collection of classroom or minor data.

## Current capabilities

- Create and manage local sessions with purpose, context, planned duration,
  operating mode, retention information, and versioned consent grants.
- Record one continuous local take with camera, microphone, motion, and resource
  status supplied by Apple frameworks.
- Report direct observations for framing, stability, light, visual availability,
  and basic audio signals, including missing and unavailable states.
- Require device-owner authentication before showing local app content.
- Attach reflection notes to time points or time ranges in local media.
- Import local media through a bounded copy operation.
- Export a metadata-only `.videographrstudy` package with declared file
  membership, SHA-256 digests, and provenance.
- Browse a German-language reference catalogue for recording methods, technology,
  and external devices.

Evidence-safe mode is the default. Experimental mode stores separately labeled,
rule-based hypotheses only when protocol metadata is present. Those hypotheses do
not determine recording readiness, consent, export authority, or reflection content.

## Limitations

- Simulator runs use synthetic capture observations and reject recording attempts.
- Camera and microphone capture, audio routes, interruptions, background behavior,
  file protection while locked, storage pressure, thermal behavior, and long takes
  still require physical-device validation.
- The app supports one local operator. It has no accounts, roles, remote
  administration, synchronization, portal upload, or multi-camera workflow.
- If the app is terminated during a take, the partial file is kept unverified. In
  Reflect the operator can check and attach it, or discard it. Whether such files
  are playable has not been validated on devices.
- The app does not edit recorded media.
- Study-package export does not include the recorded or imported MP4. The app
  currently has no separate video-export operation.
- Experimental output has no human-rater or psychometric validation.
- No educational-effectiveness study has been completed.
- Final 1024 by 1024 App Store icon artwork is not present.
- Stored schemas and interfaces may change during the alpha series.

## Requirements

- macOS 14 or newer for the Swift package
- Xcode with an iOS 17 or newer SDK for the app build
- Swift 5.9 or newer
- Python 3.10 or newer for repository hygiene checks
- ShellCheck for optional shell-script linting

The project has no third-party Swift package dependencies.

## Installation

Obtain a source checkout, change to its root directory, and open the Xcode
project:

```bash
cd videographr-classroom
open App/Unterrichtsvideographie.xcodeproj
```

Select the `Unterrichtsvideographie` scheme and an iOS 17 or newer Simulator,
then build and run. The installed app name is Videographr.

The app opens behind device-owner authentication. A new Simulator has no
passcode, so before launching choose Features > Face ID > Enrolled in the
Simulator menu (Touch ID on device types without Face ID). When the prompt
appears, choose Features > Face ID > Matching Face.

For a physical device, configure a development team and signing identity in Xcode.
Physical-device operation is outside the validated Simulator path documented here.

The Swift package libraries can be built without opening Xcode:

```bash
swift build --disable-sandbox
```

## Configuration

The app has no environment file, API key, service credential, or server endpoint.
User-entered configuration is stored with each local session.

| Area | Stored values |
|---|---|
| Session context | Title, purpose, subject, lesson goal, planned duration, and teaching situation |
| Operating mode | Evidence-safe or protocol-gated experimental research |
| Consent | Grant identifier, version, participant-group pseudonym, scopes, effective time, optional expiry, withdrawal, and retention |
| Capture | Operator pseudonym, readiness decision, override reason when applicable, runtime status, and take lifecycle |
| Export | Authorized content scopes, package membership, digests, provenance, and share-attempt state |

## Usage

1. Open Setup and create or select a session.
2. Enter the session context and save the required consent scopes.
3. Open Live and review the reported capture conditions.
4. Complete the spoken-audio check.
5. Record one take on a physical device, import one regular MP4 up to 20 GiB, or
   inspect the synthetic state in Simulator.
6. Open Reflect and add notes linked to the available media timeline.
7. Export a metadata-only study package when the required consent scopes are
   active. The package does not contain the video.

Learn contains the German-language reference catalogue. Info describes the
implemented evidence boundary and platform behavior.

## Repository structure

| Path | Contents |
|---|---|
| `App/Unterrichtsvideographie/` | SwiftUI app, lifecycle, Apple-framework adapters, resources, and property list |
| `App/Unterrichtsvideographie.xcodeproj/` | iOS app project configuration |
| `Sources/GuidanceEngine/` | Pure capture-observation and evidence-boundary logic |
| `Sources/SessionCore/` | Session, consent, persistence, recording, reflection, import, and export domain logic |
| `Sources/LearnContent/` | German-language reference catalogue |
| `scripts/` | Release and repository-hygiene checks |
| `docs/` | Architecture, evaluation, research scope, references, and release notes |
| `.github/workflows/ci.yml` | macOS CI job that runs the release gate |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries and
data flow.

## Development workflow

Keep deterministic domain logic under `Sources/`. Keep SwiftUI, AVFoundation,
Vision, Core Motion, LocalAuthentication, and other Apple-framework integration
under `App/`.

Build the package while developing:

```bash
swift build --disable-sandbox \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
```

The CI workflow runs on pushes to `main` and `alpha/**`, pull requests targeting
`main`, and manual dispatch.

## Testing

Run the complete local release gate from the repository root:

```bash
bash scripts/verify_release.sh
```

The gate runs:

- repository hygiene checks
- Bash syntax checks and ShellCheck when installed
- property-list and Xcode project syntax checks
- a release Swift package build
- hardware-free Xcode app-unit tests on an iPhone Simulator
- Xcode Release analysis for a generic iOS Simulator
- an app build for a generic iOS Simulator

[RELEASING.md](RELEASING.md) describes every gate step. Package-level unit suites
are maintained outside this public repository.

## Deployment and operation

There is no automated binary deployment workflow. The documented release process
creates a source-only GitHub prerelease after local validation, review of an exact
commit, and a successful CI run. See [RELEASING.md](RELEASING.md).

Normal operation is local to one iOS or iPadOS device. Session metadata, journals,
recordings, imports, and temporary export packages are stored in the app container.
The application does not upload them.

## Troubleshooting

- If SwiftPM reports a sandbox denial, use the documented
  `--disable-sandbox` commands.
- If launch shows "Zugriff blockiert", the device has neither a passcode nor
  biometric enrollment. In Simulator, choose Features > Face ID > Enrolled, then
  tap "Geräteeigentümer authentifizieren".
- Simulator warnings about camera, microphone, or motion hardware are expected.
  Simulator recording is intentionally rejected.
- Physical-device signing errors require a local Apple Developer team and signing
  configuration.

## Security considerations

Classroom video can identify students and staff. Do not place recordings, consent
documents, study packages, participant data, or identifiable screenshots in the
repository, issues, or pull requests.

The app uses device-owner authentication, iOS file-protection attributes, local
storage, scoped consent checks, and transaction-specific recording and export
state. These controls do not provide institutional identity management, legal
compliance, remote administration, or a complete retention program. Real-device
protection behavior remains an open validation requirement.

Read [SECURITY.md](SECURITY.md) before reporting a vulnerability or handling
sensitive test material.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing behavior or evidence
claims. Contributions should include focused tests, preserve the evidence boundary,
and pass `bash scripts/verify_release.sh`.

## License

Videographr is available under the [MIT License](LICENSE).
