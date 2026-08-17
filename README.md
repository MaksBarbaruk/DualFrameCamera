# Dual Camera Capture

An iOS 17+ SwiftUI application for creating a paired moment from the rear and front cameras using one multi-camera capture session, then reviewing locally persisted captures in a grid.

## Current state

The project foundation is in place: typed navigation, dependency injection, operation-aware error/progress presentation, domain and repository boundaries, and a unit-test target. The camera and feed feature implementations are actively in progress.

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the investigation results, target architecture, acceptance criteria, implementation status, and physical-device validation checklist.

## Requirements

- Xcode 26.5 or newer
- iOS 17+
- A physical device that reports `AVCaptureMultiCamSession.isMultiCamSupported` and exposes a compatible front/rear device pair

The simulator can run the UI and automated logic tests, but it cannot provide MultiCam capture.

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

## Architecture

- **Application** - dependency container, typed navigation, and shared progress/error presentation
- **Domain** - capture entities, camera state, protocols, and use cases
- **Infrastructure** - AVFoundation session and camera permission integration
- **Data** - atomic paired-asset persistence and thumbnail generation
- **Features** - Camera, Feed, and Capture Detail presentation

External dependencies are intentionally avoided. The implementation uses SwiftUI, Observation, Swift Concurrency, AVFoundation, ImageIO, and system frameworks.

