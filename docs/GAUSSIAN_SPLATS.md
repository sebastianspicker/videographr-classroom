# Experimental paused-frame perspective

For the educational rationale, evidence and a proposed seminar activity, see
[Gaussian splats and perspective taking in teacher education](GAUSSIAN_SPLATS_TEACHER_EDUCATION.md).

In Reflection, **Perspektive erkunden** pauses the selected recording and creates
a temporary Gaussian-splat scene from that frame. Use the horizontal, vertical
and distance sliders; the angle disclosure adds a small horizontal/vertical orbit.
Enable **Perspektive durch Ziehen ändern** to drag the image; dragging is off by
default so the page remains scrollable. Reset returns to the original camera.
The comparison control shows the original recorded frame.

The perspective view keeps three layers visibly apart. A diagonal hatch
marks screen area without image information: area the camera did not record
(disocclusion holes, outside the frame) and gaps that open at depth edges.
**Dehnung und Tiefenkanten markieren** tints splats amber where the displayed
footprint covers more than 1.5 times its recorded area, that is, where the
view spreads one recorded sample over more screen area, or where a splat sits
on a depth/occlusion edge. This is a display measure, not a validated error
estimate. Unmarked areas also rest on estimated depth; they are not shown to be
accurate. A top-down position map shows the virtual camera against the
recording camera and the assumed display depth range, without exaggeration;
height is given in words, and the scale is estimated, not measured. A collapsed
list of discussion prompts supports reflection; it is not an evaluation, and answers are not saved.

Loading reports extraction, model preparation, depth inference and scene assembly.
Recoverable processing failures offer retry for the same frozen moment. Missing
or incompatible models require a corrected build rather than an in-app download.

This is an inferred single-view depth surface (2.5D). It supports small nearby
perspective changes, but cannot recover hidden people or surfaces, provide a full
room reconstruction, or establish metric distances. Distortion, holes and depth
errors are expected. It is not evidence of what an unrecorded viewpoint saw.

## Enable the experiment

The session must use experimental research mode with a current acknowledged
research protocol and active research-processing and local-reflection consent.
Launch first flushes pending session changes; a failed save prevents generation.
It then rechecks the selected recording and settled paused clock. The request
freezes the saved protocol and grants; replacing them requires a fresh launch.
These conditions are checked after queue admission, before extraction/inference,
before publishing a result, on session
changes and periodically while viewing. Changing the selected recording or paused
clock invalidates the result. Closing the sheet, leaving Reflection, a memory
warning or making the app inactive clears the displayed scene. Returning to the
recording leaves playback paused. Canceled native work may finish before releasing
its temporary buffers; its result is never published.

## Prepare the optional model

Before building the iOS app, run from the repository root:

```bash
python3 scripts/prepare_gaussian_model.py
python3 scripts/prepare_gaussian_model.py --verify
```

The setup command downloads approximately 50 MB of public model files. It pins
the revision, membership, size and SHA-256 digest of each file. `--verify` is
offline. Files live in the ignored `Models/` directory; do not commit weights or
compiled models. The Xcode resource phase verifies and bundles an installed
model and its license notices without downloading anything. A build without the
model remains usable, but perspective generation reports that it is unavailable.
The build phase also removes a stale model from a reused build bundle when the
local model is absent. Core ML compiles the bundled package locally once per app
process and keeps the loaded model for later generations until memory pressure
or a memory warning releases it.
Simulator builds use CPU inference: the tested iOS 27 Simulator accelerator
backend returned an all-zero depth image without an inference error, while the
CPU path produced valid depth. Physical-device builds keep automatic hardware
selection. Neither path relaxes the checks for invalid or uninformative depth.

The model is [Apple's Core ML Depth Anything V2 Small F16 conversion](https://huggingface.co/apple/coreml-depth-anything-v2-small),
revision `cfef6f6f2a70783dedc0bfae40cecbc2052285d3`. The Small model uses
[Apache-2.0](https://github.com/DepthAnything/Depth-Anything-V2#license);
the bundle includes the license and attribution. No model files are modified.

## Architecture and data boundaries

- `ExperimentalResearch/GaussianDepthSurface.swift` owns permission policy,
  bounded relative-depth normalization, Gaussian construction and projection,
  and `GaussianEvidence`, which classifies how far a displayed splat departs from
  recorded pixels.
- `Reflect/GaussianFrameGenerator.swift` extracts an oriented frame at the paused
  time, runs Core ML off the main actor and samples matching color/depth UVs.
  A shared gate permits one native generation job at a time, including jobs
  completing after cancellation. A canceled or stale result is never published.
- `GaussianMetalView.swift` renders up to 20,000 surface-aligned Gaussian
  primitives with depth sorting and premultiplied Gaussian alpha. Each primitive
  samples the paused source frame, which is uploaded as a GPU texture, so image
  detail is not limited to the point grid. Points and frame are uploaded once;
  the vertex shader projects them, so translation changes only update camera
  uniforms. The far-to-near order is re-sorted only when the viewing angle
  changes. Rendering runs on demand. A background pass draws the diagonal hatch
  for unrecorded area, and an optional uncertainty tint colors stretched or
  depth-edge splats amber.
- `GaussianExplorationSheet.swift` owns the temporary result, comparison,
  bounded camera controls, position map, legend and discussion prompts. Frame, scene, GPU buffers and the frame texture are
  discarded on exit.

Camera orbit is bounded to 5 degrees horizontally and 4 degrees vertically
around an arbitrary display focus at the mid-disparity depth (about 1.04). The
original translation limits are 0.10 laterally and 0.08 in depth; combined movement still exposes only the
inferred surface. Reset restores the original camera exactly.

Each Gaussian is a small disc in the locally estimated depth surface. Its two
axes follow one grid step along the source columns and rows, including the depth
change towards neighbours on the same surface; a neighbour across a disparity
jump counts as another object and is never bridged. The vertex shader projects
both axes through the local perspective Jacobian, so tilted floors, walls and
desks keep covering their neighbours after the view changes instead of opening
gaps. In the source view the depth term projects to nothing: each footprint and
its texture lookup land on the source pixels under it, and the original render
matches the frame. The anisotropic covariance is inferred from one depth map,
not trained from multiple views, and slopes steeper than about 80 degrees from
fronto-parallel are clamped.

The model's robust relative inverse depth is mapped affinely in inverse depth to
the arbitrary range 0.8–1.5, so parallax stays proportional to the model output.
The estimated 55-degree vertical field of view and arbitrary depth range are
display assumptions. The recording contains no measured depth or calibrated
camera trajectory. This is not a trained multi-view 3DGS reconstruction.

No footage or generated scene is uploaded. No generated scene or image is saved
to session storage, human annotations, coding snapshots or study exports.
The existing metadata-only `.videographrstudy` contract is unchanged. Generated
views remain potentially identifying while displayed.

## Verification scope

Run the reproducible synthetic macOS checks from the repository root:

```bash
python3 scripts/verify_gaussian_splats.py --require-model --require-metal
```

This runner is manual: the release gate (`scripts/verify_release.sh`) does not run
it, so run it whenever the Gaussian sources, shader or model preparation change.

The runner builds real package sources, compiles the production generator, extracts
the production playback core and Metal shader, and generates synthetic media in
a temporary directory. It exercises geometry/orbit, authorization, launch ordering,
seek lifecycle, native inference/cancellation and rendered source alignment.
It never downloads a model. Without the required flags, unavailable optional
model/GPU checks are explicitly skipped. `--skip-model` exercises the model-free
paths; `--keep-artifacts` retains only synthetic diagnostic media/build artifacts
at the printed temporary path. Offscreen GPU packing is a test adapter, not an
execution of the UIKit wrapper.

Package tests, maintained outside this public repository, cover geometry,
surface-aligned footprints and texture mapping, occlusion edges, invalid inputs, camera bounds and authorization, plus the
footprint-stretch measure, `GaussianEvidence` and the occlusion-edge flag. The
offscreen render check compares GPU pixels with the CPU reference projection
along both projected axes, including the bilinear source-texture lookup. It also
checks that the amber marking changes only marked splats (none in the unmoved
synthetic source view) and that the hatch shader compiles and draws stripes.
The shader repeats the `GaussianEvidence` thresholds as literals; change both
together. Whether the hatch, marking, position map or prompts help learners
calibrate their claims is untested; see the hypotheses in the teacher-education
document.
Development checks exercised the production generator on macOS with synthetic
rotated portrait, unrotated 4:3 and unrotated 16:9 MP4s and the pinned model:
frame timing, orientation, aspect preservation, finite geometry and source-color
alignment. The portrait fixture also exercises the production shader,
non-frame-aligned pause times, inference, cancellation, queued cancellation,
source-view alignment and changed-perspective rendering. Model installation and
bundling were checked with present, repeated and missing-model cases.

The Xcode app-unit target also includes a real-model iOS generation test using
temporary synthetic video. It checks frame timing, aspect, finite geometry and
unchanged session media/annotations/export metadata. A missing optional model
explicitly skips this test; set `GAUSSIAN_REQUIRE_MODEL=1` in the test runner
environment to make missing weights a failure.

Two additional hosted-sheet tests require `GAUSSIAN_PRESENTATION_TESTS=1`.
They need a foreground-active Simulator scene and may require a person to
dismiss or complete the native device-authentication prompt. They do not disable
production authentication. They check generated-sheet presentation and dismissal
after consent replacement, paused-clock changes and a memory warning.
`GAUSSIAN_SNAPSHOT_HOLD_SECONDS=120` holds the generated view for up to two
minutes for external interaction checks and Simulator screenshots. Allow for
your test tool's total timeout, including Simulator startup and authentication.
UIKit
attachments alone do not prove visible Metal pixels; inspect a compositor
screenshot too. The synthetic host supplies an active
scene phase, so real background-transition behavior needs a separate check.

As of 1 October 2026, before the surface-aligned, texture-sampling renderer
(3 October 2026), the iOS Simulator build, strict package tests and direct
real-model generation checks pass on iPhone and iPad Simulators. Each default
app suite passes 29 tests, with two manual presentation tests explicitly skipped.
Separate opted-in runs on both devices pass generated-sheet presentation,
large-text rendering and consent/clock/memory-warning dismissal. Compositor
screenshots confirm visible Gaussian pixels. The user also verified original
comparison and perspective controls on iPad; a captured shifted view shows the
changed geometry and three changed translation values. Automated tap delivery
was unreliable, so this interaction evidence is manual, not an automated UI-test
pass. Orbit and exact reset are covered by geometry/offscreen-render checks;
the separate manual angle/reset check was not completed.

These are synthetic-data Simulator checks, not physical-device performance or
educational-effectiveness evidence. The hosted test fixes its scene-phase input;
it does not validate actual background transitions. The full release gate has
not been run. This is not a release candidate.
