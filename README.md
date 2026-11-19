# Oralo

**AI Teleprompter, at Your Pace**

**接着讲 — 跟随你的 AI 提词器**

Oralo is an open-source iPhone teleprompter that follows your speech, waits when you pause, and helps you return to your script after speaking freely. Speech matching runs on your device.

Oralo 是一款开源 iPhone 提词器：跟随语速、停顿时等待，自由发挥后帮助你接回原稿。语音匹配在设备端完成。

## Features / 功能

- A script library with plain-text import, editing, and automatic local saving. 稿库、纯文本导入、编辑与本机自动保存。
- Speech following, character-level highlighting, and manual cue selection. 语音跟随、逐字高亮与手动选句接稿。
- Chinese pinyin, English IPA, and pronunciation playback while preparing. 中文拼音、英文音标与备稿试听。
- Readiness checks, rehearsals, session reviews, and navigation back to the original sentence for editing. 准备检查、排练、复盘与原句编辑。
- Full-screen reading, light and dark appearances, and system language matching. 全屏提词、浅深色与系统语言匹配。
- iOS 18 or later, with native Liquid Glass controls on iOS 26 and later. 最低兼容 iOS 18，iOS 26 及以上使用原生液态玻璃控件。

## Privacy / 隐私

**Oralo does not upload your scripts or microphone audio to a developer-operated server. It does store your work locally so you can reopen it.**

**Oralo 不向开发者服务器上传你的讲稿或麦克风音频；为了保存与复盘，作品会存储在本机。**

| Data / 数据 | Current behavior / 当前行为 |
| --- | --- |
| Scripts and pronunciation notes / 讲稿与注音 | Saved in the app's local storage, including recovery copies. 保存在应用本机存储中，包含恢复副本。 |
| Rehearsal records / 排练记录 | Duration, cue events, and snapshots of the script and its pronunciation notes are saved locally. 时长、句子事件、当时的正文与注音快照保存在本机。 |
| Microphone audio / 麦克风音频 | Processed through Apple's on-device speech APIs; the app does not write recordings to files. 通过 Apple 设备端语音接口处理，App 不保存录音文件。 |
| Recognition text / 识别文本 | Used in memory for following; not saved as a transcript in rehearsal records. 在内存中用于跟随，不以转写全文形式写入排练记录。 |
| Preferences / 偏好 | Stored locally using system preferences. 通过系统偏好存储保存在本机。 |
| Accounts and tracking / 账号与追踪 | No account system, advertising SDK, or analytics SDK in this app. App 未接入账号系统、广告 SDK 或统计 SDK。 |
| Diagnostics / 诊断 | Reports contain performance counters, device/system details, and event metadata. Sharing happens only when you choose it; reports exclude the script and transcription. 报告包含性能计数、设备与系统信息及事件元数据；仅由你主动分享，不含讲稿正文或识别全文。 |

On-device speech requires a supported device, language, and installed system model. Model or voice downloads and files you select from a cloud file provider may require a network connection. If on-device recognition is unavailable, Oralo offers manual reading rather than sending audio to a cloud recognizer. App data is not excluded from system device backups; those are controlled by your device settings. Local recovery copies can retain earlier saved content.

设备端语音需要受支持的设备、语言和已安装的系统模型。模型、系统声音下载，以及从云文件提供方选择的文件，可能需要联网。设备端识别不可用时，可以手动提词，不会改用云端识别上传音频。当前实现未排除应用数据的系统设备备份，备份由设备设置管理；本机恢复副本可能保留较早保存的内容。

The implementation is available for inspection: [speech processing](oralo-ios/Oralo/Speech/), [script storage](oralo-ios/Packages/OraloCore/Sources/OraloCore/ScriptLibraryRepository.swift), [rehearsal storage](oralo-ios/Packages/OraloCore/Sources/OraloCore/RehearsalRepository.swift), and the [privacy manifest](oralo-ios/Oralo/PrivacyInfo.xcprivacy).

可通过上述语音处理、稿件存储、排练存储源码与隐私清单核对这些行为。这里描述的是当前 iOS App 的实现。

## Build / 构建

Use **Xcode 27.1** (the verified toolchain), with its iOS SDK and a simulator runtime. The deployment target is **iOS 18.0**. The app uses Apple frameworks and the included `OraloCore` Swift package; no API key or backend setup is required.

使用已验证的 **Xcode 27.1**、配套 iOS SDK 与模拟器运行时，最低部署系统为 **iOS 18.0**。App 使用 Apple 系统框架与仓库内的 `OraloCore` Swift 包，不需要 API Key 或后端配置。

1. Open `oralo-ios/Oralo.xcodeproj` in Xcode. 在 Xcode 打开该工程。
2. Select the **Oralo** scheme and an iPhone simulator, then Run. 选择 Oralo scheme 与 iPhone 模拟器，运行。
3. To run on an iPhone, select your own development team and a unique bundle identifier in Signing & Capabilities. Configure both **Oralo** and **OraloUITests** if running UI tests. 真机运行时使用自己的开发团队与唯一 Bundle ID；运行 UI 测试时也需配置 OraloUITests。

Build without signing from the repository root / 在仓库根目录执行无签名构建：

```sh
xcodebuild -project oralo-ios/Oralo.xcodeproj \
  -scheme Oralo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the core tests / 运行核心测试：

```sh
swift test --package-path oralo-ios/Packages/OraloCore
```

See the [iOS README](oralo-ios/README.md) for the usage flow, code structure, and UI tests. 模拟器可检查流程，真实语音跟随效果需要 iPhone 麦克风验证。

## License / 许可证

[MIT](LICENSE). Third-party pronunciation data retains its own notices; see [pronunciation credits](oralo-ios/Oralo/Pronunciation/Resources/Pronunciation-Credits.txt).

项目使用 MIT 许可证；第三方读音数据保留各自的许可证与来源说明。
