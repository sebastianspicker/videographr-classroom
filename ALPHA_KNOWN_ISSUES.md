# Known issues in the Videographr source alpha

This alpha is for contributors and methods evaluators who build the app themselves
and use synthetic data or data from consenting adults. It runs in the iOS Simulator
or on a development-signed iPhone or iPad. Read this page before you start.

## Before you start

- **Unlock the app in the Simulator.** The app opens behind device-owner
  authentication, and a new Simulator has no passcode. Before launch, choose
  Features > Face ID > Enrolled in the Simulator menu. When the prompt appears,
  choose Features > Face ID > Matching Face. If the app already shows "Zugriff
  blockiert", enroll Face ID and tap "Geräteeigentümer authentifizieren".
- **The Simulator cannot record.** It shows synthetic capture conditions. To test
  the Reflect and Export steps there, import a regular MP4 file of up to 20 GiB.
- **Device behaviour is not validated yet.** Recording, audio routes,
  interruptions, locking, storage pressure, heat, and long takes have not been
  tested on physical devices. Please report what you see.

## What does not work yet, and workarounds

- **No video export.** The study package contains metadata only. The app has no
  way to export the recorded or imported video.
- **One take per session.** To record again, create a new session.
- **Sharing the study package.** The package is a folder. Some share targets,
  such as Mail or Messages, may not accept it. Use Files or AirDrop.
- **Takes interrupted by a crash.** If the app is closed or crashes during a take,
  the partial file is kept rather than deleted. Open Reflect, where the take is
  listed as an interrupted recording. Choose "Prüfen und übernehmen" to check and
  attach it, or "Verwerfen" to delete it. Until you decide, the session cannot
  record a new take. Nobody has yet confirmed on a device that such partial files
  can be played back. If checking fails, the file stays in place and you can
  still discard it.
- **Dark preview after switching sessions during the spoken-audio check.** Leave
  Live and open it again.
- **A refused recording start is logged as a failed take.** If a start is refused
  after preparation, for example because the camera image is not ready yet, the
  session history shows a failed take with the reason "AVFoundation hat den
  vorbereiteten Start nicht angenommen". That reason is misleading. Wait until the
  preview shows a live image and start again.
- **Operator pseudonym default.** Live pre-fills the operator pseudonym with the
  participant-group pseudonym from the consent record. Replace it with your own
  operator pseudonym before you record.
- **Active session after a relaunch.** After the app restarts, a different
  session may open than the one you used last. Select yours in Setup.
- **Quick links in Reflect need a note.** "Aktuelle Position verknüpfen" and
  "Ganzes Video verknüpfen" use the author pseudonym and the observation note you
  entered above them. Fill both in first.
- **Placeholder icon.** The app icon is not final artwork.

## How to report a problem

Open a GitHub issue with the bug-report template. Please include:

- the commit you built, from `git rev-parse --short HEAD`
- the device model or Simulator, the iOS version, and the Xcode version
- the steps you took, what you expected, and what happened
- the exact German text of any message the app showed, copied or retyped word for
  word
- for build or test failures, the output of `bash scripts/verify_release.sh`
- for crashes, the Xcode console output from that run, or the crash report from
  Settings > Privacy & Security > Analytics & Improvements > Analytics Data.
  Check it for personal information before you attach it.

The app writes no diagnostic log of its own, so on-screen messages and the steps
you took are the most useful evidence.

Never attach classroom video, study packages, session files, consent documents,
personal data, or identifiable screenshots. Use synthetic or fully redacted
material. Report security or privacy problems privately, as described in
[SECURITY.md](SECURITY.md).
