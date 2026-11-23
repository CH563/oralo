# Privacy and local data

[English](PRIVACY.md) · [简体中文](PRIVACY.zh-CN.md) · [Project](../README.md)

The table below describes the iOS app; the macOS preview has its platform-specific notes below. **Oralo does not upload scripts or microphone audio to a developer-operated server.** It saves your work locally so it can be reopened and reviewed. There is no account system, advertising SDK or analytics SDK in the app.

| Data | Handling |
| --- | --- |
| Scripts and reading hints | Stored in the app's local files, including archive recovery copies. |
| Rehearsal / presentation records | Local timing, cue events, manual pronunciation-review decisions and snapshots of the corresponding text and hints. |
| Microphone audio | Processed in memory through Apple on-device speech APIs. Oralo does not write audio recordings. |
| Recognition text | Used in memory for following and conservative rehearsal observations; not saved as a full transcript in session records. |
| PiP frames | Rendered locally in memory. No camera capture, video recording file, frame upload or network video call is created. |
| Floating reading state | Script identity, revision, reading position and preferences are stored locally. Fixed pace does not use the microphone; voice mode starts only after an explicit action. |
| Diagnostics | Performance counters, device/system details and event metadata. Reports exclude manuscript text and transcripts. Sharing requires a user action. |

## Network and system boundaries

On-device recognition requires a supported device, language and installed system model. Oralo does not fall back to cloud recognition when that path is unavailable. Apple system model or voice downloads may require a connection.

Users can select a file from a cloud provider in the system file picker, export/share through another app, or open the GitHub source link. Those user-chosen services can have their own network and data-handling behavior. The public website and its forms are separate from the iOS app; consult the website's [privacy page](https://oralo.fun/privacy/) when using them.

App data is not excluded from system device backups. Device backup settings and recovery from a system backup are controlled outside Oralo.

## What deletion removes

- Deleting a script or session removes the applicable data from both the current archive and recovery copies. Associated floating state is stopped and cleared when its script is deleted.
- Interrupted deletion is completed before ordinary loading resumes. Stale editor/recorder writes cannot reintroduce removed records.
- Shared snapshots remain while retained records still reference them.
- **Clear rehearsal history** preserves presentation records and the snapshots they reference.
- **Delete all local data** clears app-managed scripts, pronunciation notes, records, snapshots, recovery copies and preferences.
- None of these actions erases system device backups or copies already exported to another location.

## macOS preview

The native Mac app has no account, advertising SDK or analytics SDK. Scripts, readings, preferences and rehearsal/presentation records stay in its local app sandbox. Microphone audio and full recognition transcripts are processed transiently, not recorded to files. It uses the shared deletion-safe repositories; exported files and system backups remain outside app deletion.

The floating prompt is an AppKit window, with no camera capture, screen capture or network video call. Meeting software can capture it when sharing the whole desktop. Oralo itself does not request camera, screen-recording or Accessibility access for prompting. On-device model downloads require the user's explicit action. The Settings support-information action copies version, OS, recognition mode and language, without script contents.

Inspect the [Mac speech code](../oralo-macos/OraloMac/Speech/), [local library](../oralo-macos/OraloMac/Library/MacLibrary.swift), [rehearsal storage](../oralo-macos/OraloMac/Rehearsal/RehearsalStore.swift) and [privacy manifest](../oralo-macos/OraloMac/Resources/PrivacyInfo.xcprivacy).

## Inspect the implementation

[Speech capture and recognition](../oralo-ios/Oralo/Speech/) · [Script repository](../oralo-ios/Packages/OraloCore/Sources/OraloCore/ScriptLibraryRepository.swift) · [Session repository](../oralo-ios/Packages/OraloCore/Sources/OraloCore/RehearsalRepository.swift) · [Deletion coordination](../oralo-ios/Packages/OraloCore/Sources/OraloCore/LocalDataRemoval.swift) · [Privacy manifest](../oralo-ios/Oralo/PrivacyInfo.xcprivacy)

Use non-private sample scripts for public issue reports, and review anything you choose to share. For help, visit [support](https://oralo.fun/support/).
