# 豆包五笔混输与自动上屏机制

本机豆包输入法 1.0.2 的五笔混输依赖本地候选类型和第五码顶字处理。五笔模式会生成拼音候选；前端依据前一轮候选决定是否提交前四码。本仓库原有的“超过四码就切拼音”缺少这层候选判断；2026 年 10 月 13 日的原生插件版本 3 已加入候选判断和顶字，实际配置见[本地输入规则](cloud-research.md)。

## 分析版本和范围

2026 年 10 月 13 日，使用 [REA](https://github.com/morluto/rea/blob/main/README_zh.md) 6.4.0、Ghidra 12.1.4、Node.js 24.21.0 分析本机安装文件的 arm64 副本。应用版本为 1.0.2，Wave Build Version 为 1.0.2.7。文件哈希及版本记录见 [.build/doubao-analysis/provenance.json](.build/doubao-analysis/provenance.json)。

五笔引擎使用 Ghidra 默认分析配置。前端的全局 switch 推断和 Objective-C 消息签名修复耗时较长，隔离的 REA 适配器增加了预分析脚本，禁用这两个步骤；分析配置写入证据的 `analyzer_preset`。Objective-C 字段和 Swift 候选 getter 另用 Apple 工具核对。反编译结果需结合汇编理解，变量名和部分调用签名不是原始源码。

以下是静态代码结论。具体输入样例的候选覆盖、默认设置和实际误判率仍需界面实测；不能据此保证每个拼音前缀都会被识别，也不能断言整个产品没有其他识别机制。

## 第五码顶字条件

前端函数 `commitWubiFifthCodeFirstCandidateIfNeeded` 位于 `0x100139844`。其核心条件如下：

1. 启用 `enableWubiFifthCodeAutoCommit`，当前键盘类型为五笔，并且没有正在执行续码恢复。
2. `selectedCandidates_` 为空，即当前没有已分段选中的候选。这不是“候选菜单为空”的检查。
3. 前一轮输入恰好四个字符；当前输入更长，并以前一轮输入开头。
4. 前一轮输入及新追加的后缀均通过 ASCII 字母检查，大小写字母都符合该检查。
5. 前一轮候选非空，首候选的 `dictType` 为 1 或 2；该分支的日志把其他类型称为非五笔候选。
6. 前一轮候选中没有 `dictType == 8` 的候选；出现该类型会进入日志明确标为“with pinyin candidate”的跳过分支。

条件满足后，提交前一轮首候选，并以追加的后缀重新开始输入。因此不是第四码落下时立即上屏，也不是只根据当前字符串长度决定是否提交。

按上述分支整理的逻辑示意如下，省略日志和内存管理：

```text
if 未开启第五码顶字 or 当前不是五笔 or 正在恢复续码:
    不自动提交
if 已有分段选中的候选:
    不自动提交
if 前一轮长度 != 4 or 当前输入不是前一轮输入的延长:
    不自动提交
if 前一轮输入或追加后缀包含非 ASCII 字母:
    不自动提交
if 前一轮无候选 or 首候选不是五笔类型:
    不自动提交
if 前一轮任一候选属于拼音类型:
    不自动提交
提交前一轮五笔首候选
以追加后缀开始下一轮输入
```

对应[REA 反编译结果](.build/doubao-analysis/rea-fifth-code.json)、[伪代码](.build/doubao-analysis/rea-fifth-code.c)和[汇编](.build/doubao-analysis/fifth-code-assembly.txt)均已保留。`dictType` 字段由 OimeEngine 的 `Candidate.dictType` getter 在 `0x1f130` 读取对象偏移 `0x78`，与前端的类型检查一致；它不是 `flagType` 字段。

## 五笔和拼音共享候选体系

`OimeEngine.framework` 保留了可用的 C++ 符号。REA 定位到 `wubi::Engine::BuildConvertCandidates`，地址为 `0x33bc40`。该函数先进行五笔系统词典的前缀查找，并在相应状态开启时调用 `InsertUsrPinyinCandidates` 和 `InsertExtensionPinyinCandidates`，随后加入用户五笔词典候选。

五笔系统词典查找 `WubiSysDict::PrefixSearchCandidates` 在输入长度大于四时返回。扩展拼音查找则有独立的音节切分：`InsertExtensionPinyinCandidates` 会遍历输入后缀，调用 `SyllableDict::CommonPrefixSearch`，并处理最长 64 字节的输入。这为五笔模式下继续处理较长拼音提供了代码依据。

引擎还有 `CandidateUnique` 去重、`PostProcessResultSorted` 排序及用户词典处理。具体排序权重不能仅由这些符号和存在签名误差的伪代码确定。

相关证据：

- [候选构建的 REA 结果](.build/doubao-analysis/rea-engine-build.json)和[伪代码](.build/doubao-analysis/rea-engine-build.c)。
- [五笔前缀查找](.build/doubao-analysis/rea-engine-prefix.c)。
- [扩展拼音音节查找](.build/doubao-analysis/rea-engine-extension-pinyin.c)。

## 提交后续码和界面状态

`commitPreviousWubiCandidateAndRestart` 位于 `0x100139f7c`，包含候选提交、用户词典保存、插入宿主文本及重新转换追加后缀的调用，见[REA 伪代码](.build/doubao-analysis/rea-commit-restart.c)。前端保留 `isRestartingWubiCompositionAfterAutoCommit_` 状态，并有“input cleared for wubi auto commit restart, keep candidate window visible”的处理线索，用于在自动提交和重新开始输入之间维持候选窗口。

另有 `recoverWubiInvalidContinuationIfNeeded`、`suppressWubiInvalidContinuationIfNeeded` 和 `suppressWubiEmptyConversionIfNeeded` 分支，以及隐藏候选时阻止选词、云候选更新的保护。这些分支说明续码与界面状态被专门处理；每个分支的完整触发条件尚未逐一还原。

## 对 Rime 改造的启示

要获得类似的连续输入体验，需要在前四码阶段就提供本地五笔与拼音候选，并保留候选来源类型。第五码处理应依据前一轮候选判断：遇到拼音候选保留整串；确认可顶字时提交前一轮五笔词，把新字母交给下一轮输入。还需要维护分段选择、退格、光标编辑与候选窗口状态。

当前云候选的轮次混排、重复词合并和短时缓存可以继续保留。自动上屏判断应先依据本地结果完成，让网络返回速度不会改变一次按键是否提交的决定。歧义输入仍需保守处理，并用真实输入样例验证，不能简单把四码自动上屏重新打开。

## 本地证据位置

工具、分析副本、反编译和快照位于被 Git 忽略的 `rime/.build/doubao-analysis/`。其中 `engine-snapshot.json` 和 `main-snapshot.json` 保存引擎及前端证据，`rea-session.py` 使用 REA 的 MCP stdio 接口复用分析会话。该目录适合本机继续研究；本文件随仓库同步时，原始证据需另行复制。
