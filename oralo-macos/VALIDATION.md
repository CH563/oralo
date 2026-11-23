# macOS validation history

[简体中文](#简体中文) · [Build instructions](README.md)

## Public GitHub preview preparation · 0.1.0 (12) · 2026-11-23

Source and packaged-resource scans found no private keys or credentials. The original local executable contained compiler debug-map paths. Release configuration now emits a separate dSYM and strips installed debug symbols before signing; the rebuilt universal executable contains no local home-directory paths. Packaging rejects such paths or credential patterns before creating an image. dSYMs, signing material, local data and build outputs are not included in the source commit or DMG.

The same app version and feature code were rebuilt for `arm64` and `x86_64`. Strict verification of the packaged signature, DMG integrity, destination link and executable identity passed. The SHA-256 companion belongs to this rebuilt public artifact. No app unit/UI tests, speech or meeting tests ran in this publication step; functional manual acceptance remains as described below. This is an ad-hoc, unnotarized preview, with no claim of production distribution approval.

## Private test DMG · 0.1.0 (12) · 2026-11-23

A universal Release build (`arm64` and `x86_64`) was packaged without changes to app functionality or the iOS/core sources. The compact 620 × 440-point Finder window was inspected after mounting the compressed DMG: centered text, Oralo → Applications, no Read Me entry, no horizontal/vertical scrollbars and a cream background reaching the bottom edge. Retina artwork is generated from source. Updated dmgbuild resolves the Tahoe background-bookmark incompatibility.

Disk-image verification and strict recursive verification of the app inside the DMG passed. The packaged executable matches the input build, the Applications link points to the system Applications folder, and a SHA-256 checksum is supplied. The signature is explicitly **ad-hoc**; the DMG is **not notarized** and has no Oralo-team Developer ID signature. No certificate from another team was used.

Only build, package-integrity/signature and installer-appearance checks ran. No app unit/UI automation, speech tests or meeting tests were repeated. Intel, older macOS and clean-machine first-launch behavior remain manual testing items. No commit, push, notarization upload or review submission occurred.

## Current delivery · 0.1.0 (12) · User Guide · 2026-11-23

Added a top-toolbar lightbulb and a standalone native guide window, with matching Help-menu and menu-bar entries. The localized guide covers preparation, prompting/rehearsal, floating near the camera, sharing a specific application window, checking the audience preview, and the distinction between window sharing, desktop sharing and display mirroring. Its DingTalk choice diagram is native vector UI; no personal screenshot or watermark is bundled.

Release build succeeded. No unit/UI automation, speech test or meeting test ran in this round. Guide layout and interactions await manual acceptance. No speech/reader/data logic or iOS/core sources were changed. No commit, push or publication occurred. Sharing advice was checked against [Tencent Meeting’s official guide](https://meeting.tencent.com/support/topic/374/index.html), including its video-smoothness/window-filtering caveat; this is not a claim that arbitrary meeting settings automatically hide Oralo.

## Earlier delivery · 0.1.0 (11) · 2026-11-23

The three-stage candidate is implemented and compiled for local manual acceptance. Debug and Release builds succeeded on the current Apple-silicon host. **No unit tests, UI tests, speech tests, meeting tests or scripted interaction checks were run for this delivery, as requested.** Build success and local signature verification do not establish the new flows’ runtime behavior. Earlier results below apply only to their named candidates.

Added: readiness with device-only model/microphone checks and voice/manual/paced modes; rehearsal/presentation records with safe passage lookup and user-led pronunciation review; sentence layout, original draft, export and complete pronunciation management; native settings, data deletion with recovery-copy cleanup, default modes/rates, Traditional Chinese, keyboard labels, bundled licenses and opt-in distribution configuration. The shared iOS/core sources remain unchanged. The Mac voice session adds passive rehearsal observations and lifecycle handling; matching, fast partials and delay compensation stay on the existing path.

Manual acceptance, including deletion/reopen, mode transitions, real voice/recovery and focus behavior, is pending: [checklist](MANUAL-ACCEPTANCE.md). macOS 15/27 runtime, Intel and actual meeting audio remain hardware checks. No account upload, notarization or review submission occurred; no commit or push was made.

## Earlier candidates

Validation dates: 2026-11-22–23. Mac candidate: 0.1.0 (10). Host: Apple silicon, macOS 26.6.2, Xcode 27.1 (Swift 6.4). Tencent Meeting: 3.48.1. Minimum deployment target: macOS 15.0.

## Bilingual library layout review

Candidate 0.1.0 (10) was checked in 16 UI combinations: Chinese/English, light/dark, grid/list, and 900/1120-point window widths. Isolated fixtures cover a short mixed-language script, long Chinese/English titles, a 7,500-character + 2,700-word script, a 7,600-word script, and an empty draft. Card/row bounds passed; screenshots were inspected for truncation and contrast. Grid excerpts remain two lines; list excerpts remain one line. Long titles retain intentional truncation (two grid lines / one list line) and now offer their full text in a native hover tooltip.

The English four-column grid exposed an awkward break between "About" and "51 min." Nonbreaking spaces keep the duration together when metrics wrap. Counts and durations remain visible in both appearances. No speech, reader, floating-window or meeting test was run in this review.

To repeat only this UI review, run `python3 scripts/check_library_layout.py --derived-data <temporary-build-directory> --result-bundle <new-result-bundle.xcresult>` from the Mac project directory. The helper seeds unique disposable test libraries and removes them afterward. The UI test skips without these fixtures; it never uses the regular library.

## Preparation alignment update

Candidate 0.1.0 (8) adds a native left/center/right segmented control to the preparation action bar. The speech-language menu starts at the title/body inset, with its visible label removed and its accessibility label retained. Narrow widths can show the pronunciation action as a symbol to keep the row intact.

Alignment is a local, whole-script reading preference shared with presentation and floating views. It changes TextKit paragraph styling, not manuscript content. Targeted checks passed for actual glyph movement, selection preservation, ruby anchors, IME composition, resize/appearance refresh and preference restoration. Existing speech sources, the ruby drawing implementation and iOS build 14/core sources remain unchanged. No live speech or meeting test was repeated for this UI change.

Chinese and English UI checks passed at a 900-point workspace width: all three alignment actions stay on one row, the language menu aligns with the title, manuscript text stays unchanged, the selection restores across application relaunch, and light/dark preparation layouts remain usable.

## Compact library cards

Candidate 0.1.0 (9) limits grid-card manuscript excerpts to two lines, with trailing truncation. The previous fixed 270-point card becomes a 220-point minimum-height card, allowing long titles or metrics to grow instead of clipping. This update only changes library layout.

## Workspace UI update

The Mac workspace now opens with a concise optional welcome page, then a standalone library. Grid/list preference is persistent, search matches titles and body text, and opening or creating a script enters the split editor. Going back flushes edits before navigation. Settings are available through the native application menu and Command-comma; the workspace has no settings button.

The toolbar follows native Mac conventions: neutral symbol controls for compose, import, view layout, search, presentation and deletion. Liquid Glass is supplied by standard system toolbar/button styles on macOS 26+, with native controls on macOS 15. Color is reserved for selection and intentional primary actions such as the welcome continuation or saving a pronunciation.

The editor sidebar uses a unified native title bar: its glass background continues behind the traffic-light controls and sidebar toggle, instead of beginning beneath a separate title strip. The welcome action uses the primary text color when its window is inactive so that the native neutral button remains readable.

Chinese and English were exercised in an actual 900-point-wide window, with long manuscript titles and light/dark appearances. Toolbar and editor action frames remain on one line. Grid titles have an intentional two-line limit, excerpts two lines, and list titles one line. Search uses `NSSearchField`, including its native focus and clear behavior; Command-F moves focus to it. The layout picker hides its visible label to avoid English words wrapping beside the icons, while retaining its accessibility label.

## Compact quick settings and persistence

Candidate 0.1.0 (7) removes inline notes, scrollbars and expanded custom-color fields. Size presets and dimensions share a row. Five position buttons offer camera alignment and four screen corners. Presentation provides font, spacing, palette, appearance and mirror shortcuts, with independent font/spacing and shared colors.

Real coordinate clicks identified a focus problem in the default minimal color-well popover: selecting a color activated Oralo. The delivered control instead opens Apple's native `NSColorPanel`, created with `.nonactivatingPanel` in its initializer. It is owned by the settings window, closes with those settings, and follows Oralo's light/dark appearance. No private window APIs, foreground-activation workaround, or global input hooks are used.

Eight unit/integration checks passed, covering all preferences, invalid-value fallback, opaque native color conversion, corner placement on an offset display, settings geometry, actual TextKit reflow with pronunciation anchors, and existing import/save/recovery regressions. Separate UI checks passed for native color selection and reopening from both readers; Chinese/English single-row size controls and four-corner placement; retained sentence through settings changes and return to presentation; and dark appearance including the system palette.

A full application-termination/relaunch UI case passed for reader and floating text size/spacing, custom color, mirror, background transparency, appearance, window size/position, welcome preference, library layout and compatibility-recognition choice. Mirror and compatibility were the two session-only preferences found during this audit and are now persisted. Native color-panel mode is saved when its panel closes. Speech-language preference remains in the saved manuscript.

Real screen-coordinate clicks on pick-up, opening settings, size presets, all four corners, near-camera placement, preset color, native color-panel opening/selection/closing, transparency and closing settings kept Tencent Meeting frontmost. A further coordinate-click check passed for font size, line spacing, mirror, the appearance dropdown, and switching/reopening the native color-slider mode. Setting the panel color before restoring its mode fixed AppKit automatically replacing grayscale with RGB on reopen. This checks foreground identity; it does not establish live call audio or keyboard-focus behavior in every third-party input field. Recognition and pronunciation source files, and the iOS build 14/core sources, are unchanged. No live microphone test or meeting was started in this round.

## Floating appearance update

Candidate 0.1.0 (5) adds persistent extra line spacing (0–24 pt, default 5), five adaptive highlight colors and custom opaque sRGB input. Hex validation rejects incomplete or alpha values; RGB controls and hex input share the same stored color. Custom editing stays inside the nonactivating panel. Its header remains visible while the controls scroll, and placement favors a position outside the prompt within the current screen.

Seven unit/integration checks passed: the four existing MacFlow cases plus persistence/fallbacks, actual TextKit reflow/recolor with a running synthetic recognition session and IPA anchors, and settings geometry on standard/small displays. The normal reader keeps its independent default spacing and palette. Speech adapters, pronunciation layout and iOS/core sources are unchanged; only the Mac reader's display parameters were extended.

The Chinese/English UI flow passed for line spacing, preset selection, custom hex application, closing/reopening controls, unchanged current sentence, resize and return to the main reader. Dark appearance with the amber preset passed. A targeted rerun of real coordinate clicks, including preset highlight selection, passed while keeping Tencent Meeting frontmost; an earlier pass observed Finder become frontmost during camera placement, with no product code change between those runs. This round did not repeat the live-microphone check because capture/recognition code was unchanged.

## Reader and floating UI update

Candidate 0.1.0 (4) uses neutral native glass controls for presentation, a compact wave/status indicator, adaptive transport controls and a reading-settings popover. The floating window adds a direct camera-placement button and a draggable status region. A native segmented picker, current dimensions, font size and background-only transparency share one nonactivating adjustment panel. The resize corner uses the system diagonal resize cursor. Reduce Transparency makes the background opaque and disables its transparency slider; VoiceOver keeps controls available.

The four MacFlow cases passed. The updated UI checks passed for Chinese/English presentation at narrow widths, all three floating presets, continuous corner resize, unchanged sentence across resizing and return to presentation, pronunciation save/reopen/presentation, and dark appearance. Coordinate clicks on pick-up, adjustment controls, size selection, camera placement and transparency preserved Tencent Meeting as the frontmost application. Speech adapters, the reader's TextKit/highlight/ruby implementation and the iOS/core sources are unchanged.

The opt-in live microphone UI check passed on candidate (4): actual capture continued with Tencent Meeting foreground; hovering revealed controls, and real coordinate clicks paused and resumed capture without activating Oralo. The fixture recognizes both listening and off-script capture states and can reopen a restored, closed workspace through the native Window menu. No meeting was created or joined, so this result does not establish remote-participant audio or human-paced speech accuracy.

## Verified

| Area | Evidence |
| --- | --- |
| Shared behavior | All 115 existing OraloCore tests passed. The iOS target and core sources were not modified. |
| Mac integration | Four Swift Testing cases passed: import/native text input and long-document layout; pronunciation edit-save-reopen and deletion recovery; camera/window geometry; follow/recovery and stale callback rejection. |
| Text input | UTF-16 import and native text insertion persisted; IME marked text was withheld until commit, and the final Chinese text survived reopening. |
| Workspace UI (candidate 3) | Six workspace/UI cases passed across the update runs: welcome, grid/list persistence, title/body search and save-return; Chinese/English narrow-window layout; prepare/present/float/return; pronunciation edit/listen/save/reopen; dark appearance/Tencent coexistence; floating-control clicks without activating Oralo. The separate real-capture UI check passed on candidate 0.1.0 (2). |
| Floating placement | Standard/wide presets, transparency control and camera placement were exercised. Standard panel measured 520 × 240 pt. Geometry tests cover a side Dock and an unavailable external display. |
| Microphone UI | On candidate 0.1.0 (2), the opt-in test passed with the ordinary Mandarin on-device speech model installed. With Tencent Meeting foreground, hovering revealed the controls; actual clicks paused and resumed recognition without activating Oralo. No audio was saved. |
| Sustained capture | In candidate 0.1.0 (2), five Mac integration/hardware tests passed in the hardware run. Capture continued for 180 seconds while Oralo was hidden and Tencent Meeting remained running: 1,805 audio buffers arrived. A subsequent 15-second restart check also passed. This is a short background stability check, not a full-length spoken meeting test. |
| Privacy | Tests use isolated libraries. No app server, account, analytics, camera capture or screen capture was added. Public project files contain no local home-directory paths or credentials. |

The default UI suite skips the opt-in microphone test. It was run separately with `TEST_RUNNER_ORALO_VALIDATE_LIVE_AUDIO=1`; a skipped default test does not stand in for the hardware result. The English keyboard fixture temporarily selects ABC and restores the previous input source after testing. Oralo itself does not change the user's input method.

## Fixes found during background-use checks

- The original SwiftUI settings popover activated Oralo when clicking a size preset. Settings now use a second nonactivating AppKit panel. Width, camera placement, transparency and closing settings were verified through actual screen-coordinate clicks from Tencent Meeting's foreground context.
- Hovering in an inactive floating window did not consistently reveal its controls. A local AppKit tracking area with `activeAlways` now tracks the mouse inside the panel; it does not install a global keyboard or mouse hook.
- Borderless panels remove the unused native title-bar area above the floating content and settings. The custom drag and resize handles remain available.
- The bundled approved app icon was not linked by the generated Info.plist. `CFBundleIconFile` is now explicit. The Mac icon uses the approved iOS artwork with a macOS tile/margin; the menu-bar template keeps the same folded paper, quotations, reading lines and speech-bubble tail.

These checks establish the frontmost application's identity, not arbitrary keyboard-focus behavior in every meeting control. Input and full-screen combinations still need a human trial.

## Limits of this validation

- No Tencent meeting was created or joined. Foreground coexistence and an active recognition session do **not** establish remote-participant audio quality or simultaneous live microphone use in an actual call.
- The shared alignment/recovery logic passed regression tests; human-paced Mac speech latency and off-script recovery still need a spoken trial. iOS build 14's earlier device results are not claimed as Mac measurements.
- The preview button was exercised and its system-speech path checked; perceived pronunciation quality requires listening by a person.
- macOS 15/27 runtime behavior, Intel Macs, external webcams, Bluetooth route changes, multiple physical displays and third-party full-screen/Stage Manager combinations were not tested on hardware.
- Transparency is background-only; Reduce Transparency intentionally uses a solid background. Entire-screen sharing can include the prompt.
- Distribution signing, notarization and Mac App Store submission are outside this local development phase.

## 简体中文

已完成的基础流程：新建 / 导入 → 编辑 / 拼音与音标 / 试听 → 保存 → 演讲 → 悬浮 → 返回演讲。桌面窗口与悬浮窗使用同一个识别会话，切换和调整大小不重新开始识别。iOS build 14 与共享核心保持原样。

建议下一次真实试用按以下顺序进行：

1. 打开示例讲稿，先在演讲页正常读两段；加速、停顿，再自由发挥一句，跳到后文继续读。
2. 切换悬浮窗，点「靠近摄像头」，调整宽度、字号和透明度；确认当前读句位置不丢失。
3. 在你自己的腾讯会议测试通话中，同时检查提词是否继续跟随，并请另一端确认人声正常。分别测试内置麦克风与常用耳机。
4. 结束 Oralo 收音，确认会议麦克风仍然正常；再次开讲，确认能接回保留的位置。
5. 如需共享屏幕，先检查腾讯会议实际共享预览。不要把「在本机可见」理解为「远端看不见」。

候选版 11 已接入准备检查与排练复盘，等待人工验收；此前的测试结果仅对应各自注明的旧版本。设备选择仍使用系统设置，长时间真实通话与新流程表现尚待人工确认。

## API references

- [Native macOS toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [System Liquid Glass adoption](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Native AppKit Liquid Glass](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [AppKit NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [Nonactivating panels](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- [Keyboard focus only when needed](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)
- [Window collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- [On-device SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
