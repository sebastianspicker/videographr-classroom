# Research gap inventory

This inventory separates current implementation from evidence that still requires
device or study work. "Unit-tested" refers to package suites that are maintained
outside this public repository; a public checkout can rerun only the app-unit
tests and the release gate.

| Area | Current implementation | Current evidence | Required next evidence |
|---|---|---|---|
| Capture planning | Setup records purpose, context, duration, mode, retention, and consent. | Unit-tested domain contracts | Physical-device usability under an approved protocol |
| Continuous recording | Local single-take lifecycle, observations, timestamps, and media-linked notes | Unit-tested transactions and Simulator compile integration | Finalization, interruption, audio-route, lock-state, and long-take device tests |
| Capture observations | Direct framing, light, stability, and audio availability with missing states | Unit-tested deterministic logic | Declared thresholds and false-ready rates from a staged adult device corpus |
| Reflection | Four analysis fields and time-linked annotations | Unit-tested model behavior and asserted Simulator UI | Task-completion, workload, and reflection-quality study |
| Experimental hypotheses | Isolated, protocol-gated, and excluded from readiness and authority | Unit-tested evidence boundary | Declared codebook, independent trained raters, reliability, and held-out validation |
| Speech intelligibility | Basic audio levels and user-confirmed playback only | Signal logging | Separately designed audio study |
| Consent and governance | Scoped grants, expiry, withdrawal, retention metadata, and export checks | Unit-tested controls | Institution-specific legal, privacy, safeguarding, and operational review |
| Educational outcomes | Not implemented as a measure | No evidence | Outcome study |

## Physical-device program

Use consenting adults and keep raw media outside the repository. Include the oldest
supported iPhone, a current iPhone, and a supported iPad form factor. Cover
orientations, lighting conditions, framing patterns, internal and external audio
routes, interruptions, backgrounding, lock state, storage pressure, and a
60-minute take. Report results by device and condition.

## Human validation

Before interpreting experimental hypotheses, declare the construct and codebook,
train independent raters, establish inter-rater reliability, and evaluate a
participant-separated holdout set. Human-observation frameworks remain human
procedures unless a separate validation study establishes another use.

## Claims not supported

Do not describe the candidate, its recordings, or its output as research-ready,
scientifically validated, internationally comparable, or a measure of teaching
quality. Do not infer speech intelligibility from audio-level values.
