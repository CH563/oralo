# 隐私与本机数据

[English](PRIVACY.md) · [简体中文](PRIVACY.zh-CN.md) · [项目介绍](../README.zh-CN.md)

下表描述 iOS App，macOS 预览版的平台差异见下方说明。**Oralo 不向开发者服务器上传讲稿或麦克风音频。** 为了重新打开和复盘，作品会保存在本机。App 不接入账号系统、广告 SDK 或统计 SDK。

| 数据 | 处理方式 |
| --- | --- |
| 讲稿与注音 | 保存在应用本机文件中，包含存档恢复副本。 |
| 排练／演讲记录 | 本机保存时长、句子事件、用户主动核对读音的结果，以及对应正文和注音快照。 |
| 麦克风音频 | 在内存中通过 Apple 设备端语音接口处理，Oralo 不写入录音文件。 |
| 识别文本 | 在内存中用于跟随及保守的排练观察，不作为转写全文写入过程记录。 |
| 小窗画面 | 本机内存渲染，不采集相机、不生成录像文件、不上传画面、不建立网络视频通话。 |
| 小窗阅读状态 | 本机保存稿件身份、版本、位置与偏好。定速模式不收音，语音模式由用户明确开启。 |
| 诊断报告 | 包含性能计数、设备／系统信息和事件元数据，不含讲稿正文或识别全文，只有用户主动分享才会导出。 |

## 联网与系统功能的边界

设备端识别需要受支持的设备、语言与已安装的系统模型。设备端能力不可用时，不会改用云端识别。Apple 系统模型或声音下载可能需要联网。

用户可通过系统文件选择器读取云盘文件，使用系统分享面板导出到其他 App，或主动打开 GitHub 源码链接；这些服务可能有各自的联网和数据处理方式。官网及其表单与 iOS App 分开，使用网站时请查看其[隐私说明](https://oralo.fun/privacy/?lang=zh)。

当前实现没有将应用数据排除出系统设备备份。设备备份设置及从系统备份恢复数据，不由 Oralo 的本机删除操作控制。

## 删除会清理什么

- 删除稿件或会话记录时，会从当前存档与恢复副本中清理对应内容；删除稿件也会停止并清理其小窗状态。
- 删除中途被打断，重启后先完成删除再正常加载；过期的编辑／录制保存任务不能重新写回已删除记录。
- 仍被保留记录引用的共享快照会保留。
- **清空排练记录**会保留正式演讲记录及其引用的快照。
- **删除全部本机数据**会清理 App 管理的讲稿、注音、记录、快照、恢复副本和偏好。
- 上述操作不会删除系统设备备份，或已经导出到其他位置的副本。

## macOS 预览版

原生 Mac 版同样没有账号、广告 SDK 或统计 SDK。讲稿、注音、偏好及排练／演讲记录保存在应用本机沙盒中；音频和识别全文只短暂处理，不写成录音或全文文件。Mac 复用防止旧副本恢复的删除逻辑；已经导出的文件和系统备份仍不属于 App 删除范围。

悬浮提词使用 AppKit 窗口，不采集相机或屏幕，也不建立网络视频通话。共享整个桌面时，会议软件可能把它一并采集。Oralo 提词本身不申请相机、屏幕录制或辅助功能权限；下载设备端模型由用户明确触发。设置中的支持信息复制只包含版本、系统、识别模式及语言，不包含稿件内容。

可检查 [Mac 语音代码](../oralo-macos/OraloMac/Speech/)、[本机稿库](../oralo-macos/OraloMac/Library/MacLibrary.swift)、[排练记录存储](../oralo-macos/OraloMac/Rehearsal/RehearsalStore.swift)与[隐私清单](../oralo-macos/OraloMac/Resources/PrivacyInfo.xcprivacy)。

## 可以检查的源码

[语音采集与识别](../oralo-ios/Oralo/Speech/) · [稿件存储](../oralo-ios/Packages/OraloCore/Sources/OraloCore/ScriptLibraryRepository.swift) · [过程记录存储](../oralo-ios/Packages/OraloCore/Sources/OraloCore/RehearsalRepository.swift) · [删除协调](../oralo-ios/Packages/OraloCore/Sources/OraloCore/LocalDataRemoval.swift) · [隐私清单](../oralo-ios/Oralo/PrivacyInfo.xcprivacy)

公开反馈请使用不含隐私的示例稿件，并在主动分享前检查内容。需要帮助可查看[支持页面](https://oralo.fun/support/?lang=zh)。
