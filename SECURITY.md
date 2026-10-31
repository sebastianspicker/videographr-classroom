# Security policy

## Supported version

| Version | Support |
|---|---|
| `0.1.0-alpha.1` | Source alpha with best-effort review |

This source alpha has not completed physical-device, signing, distribution, or
institutional deployment validation.

## Data model and network scope

| Data | Location | Network behavior |
|---|---|---|
| Sessions, consent, observations, annotations, and experimental history | Local Application Support storage | No upload path |
| Recorded or imported video | Local app container | No upload path |
| Visual analysis | On-device Apple Vision | No cloud computer-vision service |
| Metadata-only study package | Temporary local package presented to the system share sheet; no video payload | Destination is selected outside the app |
| Analytics, crash reporting, and portal integration | Not implemented | None |

Classroom video may identify students and staff. Institutions remain responsible
for consent, legal basis, safeguarding, access control, retention, secondary use,
device management, and incident response. The implemented consent and storage
controls do not establish legal or institutional compliance.

## Implemented controls

The app:

- requests device-owner authentication before showing the local interface and
  after returning from the background
- covers app content while the scene is inactive
- uses versioned, scoped consent grants with effective time, optional expiry, and
  withdrawal
- freezes the exact grant identifiers required for a prepared recording and
  revalidates them before capture and finalization
- applies backup-exclusion and iOS file-protection attributes to stored artifacts
- attaches finalized media only after media inspection succeeds
- assigns recording, import, deletion, and export work to specific transactions
- retains explicit incomplete or unknown states after interrupted operations
- keeps the media of a take interrupted by app termination, unverified, until the
  operator attaches it after a consent recheck and media inspection, or discards it;
  deleting the session also deletes that media, at the latest during the next
  launch's reconciliation if the immediate removal fails
- limits external imports to 20 GiB and copies from one opened regular-file
  descriptor
- stores observation and experimental histories in bounded journals
- builds each export at a unique path with declared membership and SHA-256 digests
- records a durable export attempt before presenting the system share sheet
- accepts only the first terminal outcome for a share attempt
- requires a confirmed operation to delete a session and its validated local media

A system share result is not a delivery receipt. An unresolved result after
relaunch remains unknown. The durable attempt record remains in local session
state and is not part of the shared package.

## Security limitations

- Device-owner authentication is not an institutional identity or role system.
- The app has no remote administration, centralized policy, or revocation service.
- File protection, lock-state behavior, interruption recovery, and deletion must
  still be verified on managed physical devices.
- A compromised, already-unlocked device is outside the app's access boundary.
- The repository does not supply signing, distribution, monitoring, backup, or
  incident-response infrastructure.

## Reporting a vulnerability

Do not disclose security-sensitive details in a public issue or pull request.

Use the repository's GitHub **Report a vulnerability** flow for a private report.
Read-only API verification on 2026-08-09 confirmed that private vulnerability
reporting is enabled. That check did not prove notification delivery, named triage
ownership, acknowledgement, or response time. Maintainers must complete a synthetic
submission and acknowledgement test before treating the route as monitored.

A report should include:

1. Affected version or commit, if known
2. Description and impact
3. Minimal, non-destructive reproduction steps
4. Relevant synthetic or redacted evidence

Response times are not guaranteed for the alpha.

## Out of scope

- Missing institutional legal or privacy workflow features already documented as
  product limitations
- Synthetic Simulator behavior
- Device-owner compromise after successful device authentication
