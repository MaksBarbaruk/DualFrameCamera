# Dual Camera Capture

An iOS 17+ SwiftUI application that keeps the front and rear cameras live in one `AVCaptureMultiCamSession`, captures a rear frame followed by a front frame at a monotonic 1.5-second target, and stores the results as one locally persisted moment with two independent assets.

The project has no third-party dependencies. It uses SwiftUI, Observation, Swift Concurrency, AVFoundation, Core Image, ImageIO, and the file system.

## Current state

The Clean Architecture foundation, polished camera/feed/detail UI, production-shaped MultiCam engine, timed paired-frame capture, cancellation-safe lifecycle, atomic local persistence, downsampled thumbnail pipeline, and typed capture-to-review navigation are implemented.

Generic simulator and iOS device SDK builds succeed with complete strict-concurrency checking. The complete functional and visual device checklist passed on an iPhone 16 Pro running iOS 26.6; the validation record is included below.

- [Implementation guide](IMPLEMENTATION_GUIDE.md) — architecture, capture sequence, concurrency ownership, navigation, persistence, trade-offs, and extension points
- [Investigation and status plan](IMPLEMENTATION_PLAN.md) — target acceptance criteria, current evidence, and device-validation record

## Feature walkthrough

- Rear-first dual-camera stage with a front picture-in-picture preview
- Animated live-preview swap that does not change rear-first capture order
- Rear-camera torch toggle with lifecycle and thermal-safe shutoff
- Shutter enabled only while both camera streams are ready
- Hold-steady progress treatment during the 1.5-second sequence
- Explicit permission, unsupported-device, interruption, runtime-error, and pressure states
- Adaptive Moments grid with bounded, off-main thumbnail decoding
- Detail screen that swaps the display priority while preserving both source files
- Automatic navigation to the newly persisted pair
- State-driven, Reduce Motion-aware transitions and haptic feedback

## Requirements

- Xcode 26.5 or compatible newer version
- iOS 17+
- A physical device that reports `AVCaptureMultiCamSession.isMultiCamSupported` and exposes a compatible front/rear device pair

The app is portrait-only in this version so capture connections and the presentation have one verified orientation contract. The simulator can run the UI and automated logic tests, but it cannot provide MultiCam capture.

### Device support statement

Support is determined at runtime rather than from an optimistic model-name allowlist. A device is accepted only when it:

1. runs iOS 17 or later;
2. reports MultiCam support;
3. exposes a front/rear pair in `supportedMultiCamDeviceSets`;
4. accepts the selected inputs, outputs, connections, and sustainable hardware budget.

Physical-device validation was completed on an **iPhone 16 Pro (`iPhone17,1`) running iOS 26.6 (`23G71`)** on 2026-08-19. An iPhone 11 and iPhone 14 Pro Max were available as candidate devices but were not tested and are not part of the documented support claim. Runtime capability checks remain authoritative even on the tested model.

## Build

```bash
xcodebuild \
  -project CameraHomeTest.xcodeproj \
  -scheme CameraHomeTest \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

To compile the app and automated suite with the same concurrency checks used during implementation:

```bash
xcodebuild \
  -project CameraHomeTest.xcodeproj \
  -scheme CameraHomeTest \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

## Test

Select an available iOS Simulator destination in Xcode, or run:

```bash
xcodebuild \
  -project CameraHomeTest.xcodeproj \
  -scheme CameraHomeTest \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=<simulator name>' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

On the current development machine, the complete suite builds, but CoreSimulator does not materialize the test worker or launch the test host; earlier installed runtimes also reported data-migration failures. The latest command-line attempt was interrupted after 135 seconds with no test process launched. This local runtime issue does not affect the generic build. Use a healthy simulator runtime or run from Xcode when available.

## Architecture

- **Application** — dependency container, typed navigation, and shared progress/error presentation
- **Domain** — capture entities, camera state, protocols, timing policy, and use cases
- **Infrastructure** — AVFoundation session/frame adapters and ImageIO thumbnail service
- **Data** — actor-isolated atomic paired-asset persistence and in-memory adapter
- **Features** — `@MainActor` Camera, Feed, and Capture Detail presentation
- **Design System** — the dark glass visual language and reusable status/card components

The dependency direction is Features/Infrastructure/Data → Domain. `AppContainer` is the only production composition root.

## Capture and concurrency summary

The engine owns all AVFoundation mutation on one serial session queue. Rear and front delegates have independent frame queues and lock-protected continuation collectors. A unique capture reservation plus collector cancellation generations prevent backgrounding or interruption from leaving the front wait suspended or publishing a stale pair.

The rear frame timestamp establishes the target. Remaining wait time is recalculated against monotonic uptime, then the first front frame at or after the target is retained. Both frames are encoded to separate HEIF payloads in detached work and are revalidated against lifecycle state before persistence.

UI models and navigation are `@MainActor`; file transactions are isolated by the repository actor. See the [concurrency section](IMPLEMENTATION_GUIDE.md#6-concurrency-and-actor-isolation) for the ownership audit.

## Storage

```text
Application Support/Captures/<capture-id>/
  rear.heic
  front.heic
  metadata.json
```

The repository writes a hidden staging directory and publishes the complete pair with one directory move. A failed write is rolled back and abandoned staging directories are cleaned at startup.

## Automated coverage

- timing target and elapsed-work compensation;
- overlapping shutter rejection and lifecycle cancellation;
- capture success/failure state mapping;
- coordinator tab/detail invariants;
- atomic publication of two assets and metadata;
- staging cleanup and pair deletion.

## Physical-device validation

The full functional and visual walkthrough was completed on 2026-08-19 using an iPhone 16 Pro (`iPhone17,1`) on iOS 26.6 (`23G71`).

| Scenario | Result |
| --- | --- |
| Permission, MultiCam capability, and session startup | Passed |
| Simultaneous rear/front previews, portrait orientation, cropping, and front mirroring | Passed |
| Immediate rear-first capture followed by the front capture | Passed; the 1.5-second target is driven by monotonic sample timestamps and separately covered by timing-policy tests |
| Sharpness checks in daylight, indoor light, lower light, and with motion | Passed in the manual walkthrough |
| Two independent HEIF assets, Moments navigation, detail swap, and persistence after relaunch | Passed |
| Repeated captures, overlap rejection, background/foreground, and recovery behavior | Passed |
| Live preview swap and rear torch toggle, including lifecycle shutoff | Passed |
| Sustained preview/capture responsiveness and pressure handling | Passed in the manual walkthrough |

No raw timing, dropped-frame, memory, or pressure trace was supplied for publication, so this repository does not invent quantitative benchmark values. The implementation record distinguishes the confirmed walkthrough from automated timing and lifecycle coverage.

The accepted video-buffer topology favors deterministic timing and stable warm streams on the tested configuration. If a newly supported device fails the sharpness or resource-cost bar, compare a prepared photo-output topology behind the existing camera protocol before changing the feature layers.

## Submission artifacts

The assignment's real-device screen recording and three-minute architecture walkthrough are external submission artifacts and are intentionally not versioned in this source repository.

## Repository

Public repository: [MaksBarbaruk/DualFrameCamera](https://github.com/MaksBarbaruk/DualFrameCamera)
