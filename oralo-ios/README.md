# Oralo for iOS

[English overview](../README.md) · [中文介绍](../README.zh-CN.md) · [Technical guide](../docs/TECHNICAL.md) · [技术说明](../docs/TECHNICAL.zh-CN.md)

Native SwiftUI app, deployment target iOS 18.0. The verified toolchain is Xcode 27.1; the local core package requires Swift tools 6.2 or later. No remote package, API key or backend is required.

## Build and test

Open `Oralo.xcodeproj`, select the **Oralo** scheme and an installed iPhone or iPad simulator. For devices, set your own development team and unique bundle identifiers for the app and UI test targets.

From the repository root:

```sh
swift test --package-path oralo-ios/Packages/OraloCore

xcodebuild -project oralo-ios/Oralo.xcodeproj \
  -scheme Oralo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Use **Product → Test** in Xcode for `OraloUITests`. UI tests create isolated libraries, and deterministic speech fixtures are enabled only in Debug. Physical devices are needed to assess microphone latency, off-script recovery and PiP behavior with Camera or another recording app. Test both supported modern speech and the iOS 18 compatibility path.

## Source map

| Directory | Responsibility |
| --- | --- |
| [App](Oralo/App/) | Entry, welcome and appearance |
| [Library](Oralo/Library/) | Script import, editing, local saving and duration estimates |
| [Speech](Oralo/Speech/) | Microphone capture and on-device recognizers |
| [Prototype](Oralo/Prototype/) | Production reader, follow coordinator and optional diagnostics |
| [Pronunciation](Oralo/Pronunciation/) | Pinyin, IPA, inline layout and system voice playback |
| [Floating](Oralo/Floating/) | System PiP, local text frames and audio-session lifecycle |
| [Rehearsal](Oralo/Rehearsal/) | Readiness, rehearsal observations and original-sentence editing |
| [Settings](Oralo/Settings/) | Reading preferences, deletion and privacy/license views |
| [OraloCore](Packages/OraloCore/) | Text matching, state, document models, persistence and unit tests |
| [OraloUITests](OraloUITests/) | UI flow and adaptive-layout checks |

The `Prototype` directory name is historical; it contains the reader used by the app, including the model reused by voice-follow PiP. See the [technical guide](../docs/TECHNICAL.md) for implementation details and [privacy notes](../docs/PRIVACY.md) for storage and deletion behavior.
