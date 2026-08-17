# Dual Camera Capture - Investigation and Implementation Plan

## Purpose

This document is the living implementation record for the camera assignment. It separates:

- **What we want**: the intended product, architecture, behavior, and acceptance criteria.
- **What we have**: the implementation status, verified behavior, measurements, and known gaps.

The status section must be updated whenever a milestone changes materially. Hardware-only claims remain unverified until they are measured on a supported physical device.

## What We Want

### Product outcome

Build an iOS 17+ SwiftUI application with two primary screens:

1. **Camera** - show the front and rear cameras live at the same time using one `AVCaptureMultiCamSession`. A shutter action produces a paired capture: rear camera first, then front camera 1.5 seconds later.
2. **Feed** - show locally persisted paired captures in a responsive grid. Selecting a capture opens a larger review experience.

The two captured images remain separate assets at all times. A picture-in-picture composition may be used for presentation, but never replaces the source assets.

### Non-negotiable acceptance criteria

- The rear capture request is issued immediately when the shutter is tapped.
- The front capture is scheduled from a monotonic clock for 1.5 seconds after the rear capture event.
- Both delivered images are sharp under the documented supported conditions.
- The rear and front images are persisted as independent files.
- Capture, image encoding, thumbnail creation, and file I/O never block the main thread.
- Unsupported devices, missing permission, interruptions, runtime errors, and system pressure produce recoverable UI states rather than crashes or dead ends.
- The app remains usable after backgrounding, foregrounding, repeated captures, and recoverable camera-service resets.

### Target user experience

#### Camera

- Rear camera fills the primary preview.
- Front camera appears as a movable-looking picture-in-picture card; the first version may keep its position fixed.
- A clear shutter control is enabled only when the session is ready.
- Immediate haptic and shutter feedback confirm the rear capture.
- A 1.5-second progress treatment communicates "Hold steady" before the front capture.
- Permission, unsupported-device, interruption, thermal-pressure, and recovery states are presented in context.

#### Feed

- Adaptive grid with downsampled thumbnails.
- Empty state with a direct route back to Camera.
- Each tile presents both assets using a display-only picture-in-picture composition.
- Detail view supports reviewing both source images and swapping which one is visually primary.
- Delete and share are stretch goals and must not delay capture correctness.

### Architecture

The project uses a pragmatic Clean Architecture split with protocols only at boundaries that need substitution or testing.

```text
Application
  AppContainer, AppCoordinator, ProgressController

Domain
  CapturePair, CameraCapability, CaptureState
  CaptureRepository and CameraCaptureClient protocols
  CapturePairUseCase, LoadFeedUseCase, DeleteCaptureUseCase

Infrastructure
  MultiCamCaptureEngine
  CameraPermissionClient
  CameraSessionEventMonitor

Data
  FileCaptureRepository
  CaptureMetadataStore
  ThumbnailProvider

Features
  Camera
  Feed
  CaptureDetail
```

#### Concurrency model

- UI models and app navigation are isolated to `@MainActor`.
- AVFoundation session configuration and capture state are owned by one serialized camera executor.
- Capture timing uses `ContinuousClock`, not wall-clock time or a UI timer.
- File persistence and thumbnail decoding run outside the main actor.
- Delegate callbacks are bridged into structured concurrency with one continuation owner per capture request.

#### Navigation and progress

- A typed `AppCoordinator` owns the selected top-level tab and detail routes.
- `ProgressController` owns app-level recoverable errors and generic operations.
- Camera capture does not use a global loading Boolean. A dedicated state machine drives precise states such as `starting`, `ready`, `capturingRear`, `waitingForFront`, `capturingFront`, `saving`, `interrupted`, and `failed`.

### Capture investigation and intended strategy

#### Confirmed API constraints

- Multi-camera support must be checked through `AVCaptureMultiCamSession.isMultiCamSupported`.
- The selected front/rear devices must appear together in `AVCaptureDevice.DiscoverySession.supportedMultiCamDeviceSets`.
- MultiCam sessions use input-priority configuration, so each device format is selected explicitly.
- Only formats whose `isMultiCamSupported` value is true are eligible.
- `hardwareCost` and `systemPressureCost` must remain sustainable.
- The SDK does not support the naive assumption that two independent `AVCapturePhotoOutput` objects can always be added to one session. The final still-capture topology must therefore be proven on the target hardware.

#### Vertical-slice decision

Before polishing the complete feature, compare the viable capture topologies on a physical device:

1. **Prepared still-photo routing** - one preconfigured photo output routed between already-warm rear and front inputs, if the device/session accepts the required connections without preview disruption.
2. **Video-buffer still extraction** - dedicated front and rear `AVCaptureVideoDataOutput` streams with timestamped pixel buffers, controlled exposure/focus behavior, and off-main HEIF encoding.

Choose the production path from measured evidence:

- rear request-to-exposure latency;
- rear-to-front exposure interval, target `1.50 s` with a documented tolerance;
- delivered resolution and sharpness across daylight, indoor, movement, and lower-light scenarios;
- preview frame stability during capture;
- session hardware and system-pressure cost;
- repeated-capture reliability and memory behavior.

The capture engine is hidden behind `CameraCaptureClient` so the UI, use cases, persistence, and tests do not depend on which topology wins.

### Persistence design

Each capture is stored atomically in its own directory:

```text
Application Support/Captures/<capture-id>/
  rear.heic
  front.heic
  metadata.json
```

Metadata includes the identifier, creation date, capture timestamps, image dimensions, orientation, and schema version. Writes go to a temporary directory and are moved into the feed only after both assets and metadata succeed. A partial failure is rolled back.

The grid uses ImageIO downsampling and a bounded in-memory thumbnail cache. Full-resolution images are loaded only for detail presentation or export.

### Error and lifecycle handling

- Camera authorization: not determined, authorized, denied, restricted.
- Device capability: MultiCam unavailable or no supported front/rear device set.
- Session lifecycle: start, stop, background, foreground, interruption, interruption ended.
- Runtime recovery: handle media-services reset by rebuilding or restarting the session safely.
- Resource management: observe system pressure, reduce preview frame rate when appropriate, and surface critical shutdown states.
- Capture cancellation: backgrounding or unrecoverable interruption cancels the pair and prevents a partial item from entering the feed.

### Test strategy

#### Automated

- Rear capture is invoked before any suspension point in the orchestration use case.
- Front capture is scheduled for exactly 1.5 seconds later using an injected clock.
- Repeated shutter taps cannot overlap capture pairs.
- Cancellation and error transitions return the state machine to a recoverable state.
- Persistence publishes a feed item only after two independent assets are committed.
- Partial persistence failures roll back temporary data.
- Feed ordering, empty state, thumbnail requests, and view-model error mapping.

#### Physical-device verification

- Permission flow from a clean install.
- Simultaneous front/rear preview and correct orientation.
- Capture timing measured from AVFoundation/sample timestamps, not UI animation time.
- Sharpness and motion tests in daylight, indoor light, lower light, and with a moving subject.
- Ten or more repeated captures while monitoring memory, dropped frames, hardware cost, and pressure.
- Background/foreground, interruption, and thermal/resource-pressure recovery.

### Delivery milestones and commits

1. `docs: add camera implementation roadmap`
2. `chore: establish project architecture and test foundation`
3. `feat: add polished camera and feed UI shell`
4. `feat: implement resilient multicam session`
5. `feat: add timed paired capture and local persistence`
6. `test: verify capture orchestration and document tradeoffs`

The public repository will use a neutral product name and will not include company names in its repository name.

## What We Have

Last updated: 2026-08-17

### Current status

| Area | Status | Evidence / next action |
| --- | --- | --- |
| Assignment analysis | Complete | Requirements and hard constraints translated into acceptance criteria above. |
| Starter build | Complete | Default project builds successfully for a generic iOS Simulator destination. |
| Minimum deployment target | Complete | Project and test targets now deploy to iOS 17. |
| Git hygiene | Complete | `.gitignore` excludes user-specific Xcode state; existing local `xcuserdata` is intentionally not committed. |
| Clean Architecture foundation | Complete | Application, domain, data, feature-ready infrastructure boundaries, dependency container, and use cases compile. |
| Navigation and progress | Complete | Typed tab/detail navigation and operation-aware centralized error/progress presentation are implemented. |
| Camera/feed UI | Complete | Polished camera stage, capability messaging, capture progress treatment, feed states, adaptive grid, and swappable detail UI compile and were visually checked in the simulator. |
| MultiCam session | Pending | Requires implementation; simulator can exercise unsupported-state UI only. |
| Still-capture topology | Investigation required | Must be selected from real-device measurements described above. |
| Timed paired capture | Pending | Implement behind a fake camera first, then validate timestamps on hardware. |
| Local persistence | Pending | Implement atomic two-asset storage and downsampled feed thumbnails. |
| Automated tests | In progress | Unit-test target is active; initial coordinator tests pass on the iOS Simulator. Capture and persistence tests follow with those features. |
| Physical-device verification | Blocked by device availability | Known devices are currently offline; continue simulator-safe work first. |
| README and submission notes | In progress | README skeleton contains build/test steps and architecture; hardware measurements and final trade-offs remain pending. |
| Public repository | Pending | Authenticated GitHub connection is available; publish after reviewable commits exist. |

### Baseline environment

- Xcode 26.5, build 17F42.
- Starter scheme: `CameraHomeTest`.
- Starter branch: `main`, one initial commit, no remote.
- Known but currently unavailable devices:
  - iPhone 14 Pro Max
  - iPhone 16 Pro
  - iPhone 11

### Open validation items

- Determine which connected device and front/rear pair produce the best sustainable MultiCam format combination.
- Confirm the final still-capture output topology accepted by the physical device.
- Measure actual rear exposure latency and rear-to-front interval.
- Select and document the sharpness/latency trade-off for photo-quality prioritization or video-buffer extraction.
- Record tested-device models and operating-system versions in the README.
