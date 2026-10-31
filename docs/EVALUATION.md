# Evaluation guide

## Evaluation scope

Evaluate the source alpha with synthetic material or recordings of consenting
adults under an applicable protocol. Do not use classroom or minor data based on
this repository alone.

The evaluation may examine the local workflow, failure states, consent checks,
package structure, and direct capture observations. It cannot establish legal
compliance, pedagogical validity, or educational effectiveness.

## Procedure

1. Build and run the app as described in the [repository README](../README.md).
2. Create a session with context, planned duration, retention information, and
   versioned consent grants.
3. Keep evidence-safe mode selected unless the evaluation has a live protocol and
   the required experimental metadata.
4. Confirm that capture observations describe technical conditions and unavailable
   inputs without pedagogical interpretation.
5. On a physical device, record only material covered by the applicable approval
   and consent.
6. Add reflection notes linked to time points or ranges.
7. Export only when collection, secondary-use, external-sharing, and any
   content-specific scopes are active.
8. Inspect the package manifest, declared members, digests, and provenance.
9. Record missing media, unavailable signals, rejected operations, and persistence
   failures as outcomes.

## What each check establishes

| Check | Evidence |
|---|---|
| Strict Swift package tests (maintained outside this repository) | Deterministic domain contracts |
| Generic Simulator build | Compile integration |
| Physical iPhone or iPad run | Device-specific capture, permissions, protection, interruptions, and endurance |
| Staged adult pilot | Technical thresholds and failure rates under declared conditions |
| Human-rater study | Reliability and construct evidence for a declared coding procedure |
| Educational study | Outcome evidence |

## Reporting

An accurate methods statement is:

> Videographr was used as a local capture and evidence-linking tool. Technical
> capture observations were recorded as process metadata. Pedagogical analysis,
> where performed, used the study's documented human procedure.

Do not report that Videographr supplied validated IPN, TIMSS, GTI,
speech-intelligibility, learning, or teaching-quality measures.

## Local checks

```bash
bash scripts/verify_release.sh
```

This command does not replace physical-device or human-validation work.
