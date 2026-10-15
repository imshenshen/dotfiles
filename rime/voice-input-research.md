# 鼠须管语音输入与文字整理方案

鼠须管可以增加流式语音输入、说话时持续显示文字、手动编辑及智能文字整理。这需要新增 macOS 原生语音模块和前端文本协调器；Rime 的五笔、拼音和云候选继续由现有引擎处理。文字协调器负责隔离识别修订与用户编辑，决定识别或整理结果可以替换哪一段文字。

## 豆包程序中的实现线索

本机豆包 1.0.2 的程序包含 `SAMIASRRuntimeManager`、识别结果回调、离线模型管理器，以及 `ASRTypeWriter`。打字机组件保存 `currentResult`、`currentPartialResult`、`currentIndex` 等状态，日志包含 `commonPrefixCount` 和 `replaceLength`。这些是识别结果增量更新的直接线索；可以推断前端比较新旧文本的公共前缀，更新变化的尾部，并协调逐步显示。

`ContiguousRanges` 有插入、删除和语音区间判断，另有删除按键和文字变更跟踪、`ModifyPair` 记录。程序还包含智能整理的流式结束状态、缓存、焦点和输入源切换中断、宿主文字校验、撤回登记和撤回验证组件。这些线索支持“识别、文字增量更新、编辑跟踪、整理与撤回分别处理”的架构解释，不能仅凭名称确定每个分支的完整算法或实际使用的模型。

语音识别结束后，输入法进程仍可处理输入事件。豆包的 `KeyboardGlobalContextServices.textDidChange` 日志保留 `usedASR`、`modifyPairPreSnapshot_` 和修改状态，并明确在 `usedASR` 变为 false 时清除跟踪。这说明编辑记录的生命周期与录音会话分开；它不是通过继续监听声音判断修改。输入事件与编辑器提供的光标、附近文字或辅助功能快照可用于比较修改前后文本，但对不提供可靠文本范围的应用只能停止跟踪或降级，不能保证任意宿主和无限时间的追踪。

程序包含 `ModifyPairUploadRequest` 和 `/api/v3/context/ime/modify_pair/v2` 路径，支持将原文与修改后文字形成修改对的推断；单凭这些线索不能确认每次编辑是否上传、适用开关或服务器如何使用数据。

本机版本明确包含 `SAMIASRRuntimeManager`、SAMI Core 调用及离线模型路径检查，在线语音网关包括 `frontier-audio-ime-ws.doubao.com` 和 `frontier-audio-ime-quic.doubao.com`。可确认它接入 SAMI SDK 和豆包专用网关，且具有离线识别路径。具体云端模型版本及其与火山引擎公开 API 的对应关系尚未核实；智能整理的具体语言模型版本也不能由 `SmartOrganizeClient` 名称确定。我们若接入这类云服务，应使用[火山引擎公开豆包语音接口](https://www.volcengine.com/docs/6561/79817)及自己的服务配置。

上述线索来自本机程序的字符串、Objective-C 元数据及汇编定位，保存在 `.build/doubao-analysis/`；本次没有完整反编译语音模块，也没有录音测试豆包的实际语音准确率。

## 本机语音能力

2026 年 10 月 13 日，使用本机 Xcode SDK 编译只查询支持信息的 Swift 探测程序，结果如下：

| 项目 | 本机结果 |
| --- | --- |
| SpeechTranscriber 可用 | true |
| 支持中文地区 | zh_CN、zh_TW、zh_HK |
| 已安装中文模型 | zh_CN、zh_TW |
| 旧版中文识别接口支持设备端识别 | true |

因此第一版可以使用 Apple 语音能力，不必先选购云语音服务。新 API `SpeechAnalyzer`、`SpeechTranscriber` 要求 macOS 26；其他电脑需要分别检查系统、设备和语言支持，必要时使用旧版接口或另外的识别后端。

Apple 的 [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) 异步接收音频并输出识别事件；[volatileResults](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/volatileresults) 会为同一音频区间多次提供逐渐修订的暂定结果。旧版 [shouldReportPartialResults](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/shouldreportpartialresults) 也支持中间结果。持续显示文字可以基于这些接口完成。

探测源码和输出保存在 `.build/voice-research/`。探测只读取支持信息，没有录音、申请麦克风权限或下载模型；随后已用本地合成音频验证实际模型，得到 30 次暂定结果和 1 次最终确认；完整使用与验证记录见 [本地语音文档](voice-input.md)。

本机 macOS 本地语音方案可以先用本地签名编译运行，不以购买付费 Apple 开发者会员或语音服务 API Key 为前提。实际录音需要系统麦克风授权；Apple 对[新旧语音接口的授权要求](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)作了区分，SpeechAnalyzer 的转写模块不把声音发送给 Apple 服务器。面向其他用户正式分发时，Developer ID 签名和公证属于另一项分发要求，需按[Apple 开发者会员说明](https://developer.apple.com/support/compare-memberships/)配置。当前能力探测不等于已验证完整录音应用的权限流程。

## 持续上屏与编辑

识别事件应携带语音会话、音频段、修订版本、文本及是否最终确认的信息。前端保留三个边界：已确认文本、仍可修订的语音尾部、已被用户修改的文本。

暂定结果更新当前尾部，最终结果确认并提交相应段落。鼠须管已有 `IMKTextInput` 的 `setMarkedText` 和 `insertText` 调用；语音协调器可以沿用这些宿主接口，直接处理中文文字。语音结果不应塞入五笔编码解析器。

当用户退格、插入文字或移动光标时，协调器先结束当前尾部的自动替换，把修改后的文字交还用户控制，再为后续语音建立新插入位置。已经被用户修改的段落不再由旧识别结果覆盖。宿主应用、输入控制器或焦点改变时，会话版本发生变化，迟到结果失效。

第一版宜使用“暂定尾部显示、最终句段提交”的边界。若要像豆包一样更积极地直接替换已上屏文字，就需要增加明确的宿主范围跟踪、替换前原文校验和编辑冲突处理，并在 AppKit、浏览器、Electron 及不同编辑器中逐一测试兼容性。

## 智能文字整理

整理模块接收已经确认的一段文字，输出加标点、去口头语、调整句式或分段的结果。识别和整理分开运行，语音显示不会等待语言模型返回。整理后端可以配置本地模型或公开服务接口；具体模型、费用和中文整理质量需要单独比较。

第一版建议在停止说话后整理当前语音段，并保存原文以支持撤回。替换前检查该段仍是请求时的原文、宿主和会话版本仍一致；用户已经改过时，将整理结果作为可选择的建议。逐句自动整理可在编辑跟踪与撤回可靠后加入。

## 集成方式和实施顺序

推荐增加一个独立的 macOS 语音进程，负责录音、识别及整理服务；鼠须管前端增加桥接和文字协调器。独立进程可复用模型，并把音频与网络工作移出输入法按键路径。前端按会话校验结果、更新文字和显示语音状态。

实施分为三步：

1. 本机中文流式识别、启动停止快捷键、语音状态提示、暂定文字和最终句段提交。
2. 说话期间的退格、光标移动、手动输入、焦点切换保护，以及撤回。
3. 停止说话后的文字整理，随后评估逐句整理和可配置云语音后端。

验收需覆盖暂定结果反复修订、中文与英文混说、识别失败、录音中编辑、应用切换、迟到回调、整理时原文被改动及撤回。当前已完成 Apple 本地识别、前端流式显示、键盘编辑保护、停止 / 取消及范围校验撤回，并编译安装到本机。智能文字整理仅预留接口，没有配置后端；录音已独立于输入法上下文，跨应用时转浮窗预览；完成后检查当前输入框，无法安全写入时提供可编辑的结果与手动复制。本机设置页已验证实际麦克风输入与波形响应；按用户要求移除了通道选择，只保留设备和音量测试。持续上屏的真实麦克风验收仍需完成，实际验证范围见 [本地语音文档](voice-input.md)。
