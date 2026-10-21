# 豆包输入法词库桥接调查

调查日期：2026-10-20。目标是从鼠须管的词库管理页面明确编辑豆包词条，并与 iPhone 豆包合并。**本文件记录调查结果，尚不是已交付的双向同步功能。** 未修改真实豆包词库、账号凭证、Squirrel 安装版本或输入源配置。

## 当前交付范围：手动单向合并

2026-10-20 在完成下述调查后，已实现从 Mac 豆包的已下载侧词库预览、搜索、选择并增量合并到现有 Rime 自定义词典。实现为纯 Swift 的只读解析器，不加载豆包私有框架；不需要关闭签名库验证或新增权限。来源词删除后的本地排除、已导入词的本地编辑保护、原有混合格式及 ASR 热词选择均有回归覆盖。此范围不包括 Mac → iPhone、云端修改或单词删除。

解析器依据本轮 REA 的 Load / Visit / 单项反序列化 / 扩展头反序列化，Evidence 为 `ev_517464f374b7c5cbc288a4366eb5a81a652a40e9a78525c57389ea9ff4f95f4d`、`ev_81722143ae4d3f11bef3928f6fcbe0877f3b3beee4e9fe323e37f13ba9e407a6`、`ev_d0ef421541f9f4cc480cf97b7e45cb9d425cf81f9b9e4a944a6065d1c8325858`、`ev_813a3817ecef5fb3e2c973b903358f35a2f36e2f625dcc2ae90066e2f025f027`。另以 arm64 汇编核对 10 字节节点的相邻 child/value 边界。完整树、长度、头版本、扩展版本、UTF 编码和条目数量均先校验，未知格式关闭解析。

本机纯 Swift 只读验收得到 9,161 条记录，与原生 Visit 数量一致；可导入 9,148 条，跳过 13 条不满足编码等条件的记录；两个公开测试词都存在。合成 UI 验收通过搜索过滤、选择合并、同名本地词保留及语音热词默认关闭；验收没有修改个人词典。使用方式见 [编译文档](build-squirrel.md#豆包个人词库合并2026-10-20)。以下保留完整历史调查记录。

## 版本和证据

### 后续重点：Mac → iPhone

用户试用单向导入后，明确优先解决把 Mac 整理的词库推送到 iPhone。暂不扩展单向导入范围。

再次只读检查：本机同步调度和下载版本仍为 `1792464433000`，侧词库 SHA-256 仍为 `eb602949fd8e6fabe0a830e43b6da98f3195e2cd88f494d6294f86045ad8af26`；没有新的拉取或上传证据。之前 Mac 测试词云端往返成功，仍不能证明手机收到或参与候选。

重新提取当前安装主程序的字符串，完整文件 SHA-256 为 `f73d05eefa95feaa7cc20dc9d5f9b2d8b96dc01f17c940881c4c5661c7599c9e`。`WaveAccountSync` 可见设置、模糊音、最近标点的 handler，以及独立的 `fromPlatform` 字段和 `/api/v2/sync/{last_version,pull,push}` 路径；未在该字符串清单找到常用语 handler。字符串缺失不能证明功能不存在，也不能把设置同步接口当成词库写入接口。

下一步验收必须区分：Mac 写入成功、服务端可重新下载、手机实际候选可用。需进一步查清手机拉取条件和平台属性的消费方式；常用语作为可能替代路线，也必须实际验证跨端到达，不能仅凭本地 CRUD 方法交付。

本机安装目录 `/Library/Input Methods/DoubaoIme.app`，应用版本 1.0.2。实际安装的 OimeEngine 完整文件 SHA-256：

```
f0da51a994a8a78b2955a45f14ddabc1a308bfcd4462961393c8881eb0217f62
```

本轮提取的 arm64 副本 SHA-256：

```
0cec7d2f7cf099d5c9af02707da494f01eb5a9f51b9d80da0f53a667c9e4f2a7
```

与 10 月 13 日五笔调查的副本哈希不同；本轮重新提取、核对符号和 Objective-C 元数据，不能仅凭版本号认为二进制不变。证据位于 Git 忽略的 `.build/doubao-dictionary-research/`；REA 原始结果位于 `.build/doubao-analysis/rea-dictionary-*.json`。不要提交二进制、账号路径或个人词库导出。

## 两类词库必须区分

| 类型 | 已验证的本地操作 | 尚未验证 |
| --- | --- | --- |
| 自动学习词库 | 新版侧词库逐条遍历；本地 `usr.dat` 新增、保存；词频属性修改 | 针对单个词的跨设备删除；反向写入后 iPhone 生效 |
| 常用语 | 原生新增、查询、以删除后新增实现修改、删除、保存、重新加载 | 当前账号的常用语实际上传与 iPhone 收到结果 |

当前账号目录在 `~/Library/Application Support/DoubaoIme/EngineUserDictAccounts/` 下。只有一个账号时研究工具可自动选择；多账号必须显式选择，不按目录排序猜测当前账号。账号目录名不进入日志。

当前主要拼音学习数据位于 `usr_side_dict.dat`，并非旧工具假设的 `usr.dat`。侧词库 ID 12044、日期标记 20260710、头长 48，带 trie、词值区和扩展头；不能用旧版 64 字节 `usr.dat` 编码器重写。

原生 `UsrSideDict::PrepareSnapshot` 和 `Visit` 在禁止联网、禁止读取真实账号目录、禁止写入临时目录以外位置的子进程中验证成功。初次副本包含 6,873 组键、9,131 条词记录。记录具有音节键、词语、输入串、平台位掩码及平台属性向量；掩码的业务枚举尚未完全确认。

## 找到的本地方法

以下是私有 ABI，不是厂商对外承诺的 SDK。地址针对上述 arm64 文件。

| 方法 | 地址 | 说明 |
| --- | --- | --- |
| `UsrSideDict::PrepareSnapshot` | `0x1aec38` | 返回状态码；本轮 0 表示成功，得到 native shared_ptr |
| `UsrSideDict::Visit` | `0x1b02f4` | 按音节键遍历词条；回调返回 true 继续 |
| `UsrSideDict::ExportDictToString` | `0x1b043c` | 可导出原生可读格式；默认研究流程不保留明文 |
| `pinyin::UsrDict::Load` | `0x19a6c8` | 返回 bool；true 表示加载/创建成功，与上一个状态码约定不同 |
| `pinyin::UsrDict::Add` | `0x19f06c` | 音节 ID 向量、输入串、词语、WordInfoFlagType |
| `UsrDictBase::UpdateAttribute` | `0xfa8c4` | 可修改词频等属性，但不等于云端 CRUD |
| `CommonPhraseDict::Load` | `0xb1f2c` | 返回 bool；允许创建测试空库 |
| `CommonPhraseDict::Add` | `0xb2b14` | 输入串、UTF-16 输出和四个布尔标记；标记含义需沿上层调用核对 |
| `CommonPhraseDict::Remove` | `0xb2eb4` | 内部标记 unused，再更新属性；不是随意删除文件中的字节 |
| `CustomDictBase::Save` | `0xaefc4` | 返回状态码；0 成功。保存会清理测试中已删除的常用语记录 |

Objective-C `ImeEngine` 还暴露了更高层入口：

```
insertCommonPhrase:
removeCommonPhrase:
updateCommonPhrase:newPhrase:
fetchCommonPhrases:size:
saveCommonPhraseEdit
getCommonPhraseTotalCount
learnCandidatePinyin:Word:
saveUsrDict:
loadUsrDictForAllRunningEngines:
setUserAccountInfo:userDictPath:enableSyncDict:
```

高层方法名和类型编码已从实际安装二进制恢复；不能据此推断独立进程调用能操纵已运行的豆包进程。研究工具只调用自己的隔离引擎实例。

`CommonPhrase` 对象的属性为 `inputCode` 和 `content`。`insertCommonPhrase:` 返回整数结果，删除和修改方法返回 void，不能把“方法已返回”直接当作同步确认。REA 的参数恢复存在 Objective-C 动态调用及 C++ 返回寄存器推断误差，接口约定需同时核对 Objective-C 类型编码、汇编和隔离执行结果。

## REA 反编译结果

按用户要求，使用 REA 6.4.0、Ghidra 12.1.4、Temurin JDK 21.0.12.1 分析本轮 arm64 副本。最终成功批次关闭了 `Decompiler Switch Analysis` 与 `Objective-C Message Analyzer` 两项全局推断，保留普通静态分析；配置差异写入 `analysis_profile`。Objective-C 方法及属性名另通过原始符号、元数据和汇编交叉核对。会话已执行 `close_binary`，快照为 `.build/doubao-analysis/dictionary-snapshot.json`。

| 问题 | REA Evidence ID |
| --- | --- |
| 定时同步默认间隔 | `ev_a4bd29fee15466cd26f5415ca4a45e2b2b41bfa9ceac81e6f7157b28df2bb3a6` |
| 调度时间门槛 | `ev_a06a19b44ba2a456b4e92f8e820c477c9c0ddf51b590e2d84c12b13948eafc7d` |
| 常用语保存入口 | `ev_bab391c1c41e447f246f68d684c586a791d1243a359ba8d7d77b0e4484eb6878` |
| 常用语新增入口 | `ev_e50faf655f265c22f3bdb65de9cf3ae455ccbf9345e942a9fd3bdbb7d9cfcc8b` |
| 常用语修改入口 | `ev_0e849da4b1f6d80417ce82d76d4ee09ba33d776c8942063b6c45f2928733c7fd` |
| 上传控制流生成 | `ev_7f40caeefe1725042f8cd0fbb33e8fe9af9f65d85c7650ba79ee19a6a36d3768` |
| 开始上传任务 | `ev_76eeeacc0789dd8a1cc49c192b9028bbfe2584810d73e4ee2ef8e8e41f882477` |
| 本地清库通知 | `ev_161d6ab1394d84eca17614de06ea432bf1262e0d9240faecf76d96f107526c02` |
| 输入结束与同步调度 | `ev_6c3c16b746b61d52f2e7edfaaace7b448fa2a12e57dfea8b2eff475c12e12a8e` |
| 账号变化与加载同步状态 | `ev_087a7ff6a004ac107251b0302c58d0668a4c6b29ad6c597eb2f456a993ba2053` |
| 常用语底层保存 | `ev_e6a3e5bda2b913540a50e32318fe69548cc0c42a7d83163bf0ad20f38ecccbc5` |
| 同步类型的实际执行分支 | `ev_70cad0c299e08b8762f7cf3f613c3c5e28397016d02dc1fd30a4b80979fc8459` |
| 拼音词库就绪检查 | `ev_d6a9c0124a202765b2ea102690d4f4f0c737440f3d16e9e25dabadefe96833d2` |
| 同步公共词条属性的序列化 | `ev_1b53cb8ee5102a154f814a50455e032acba840312ddde7bf27412b728d1f3288` |
| 本地学习词的新增属性更新 | `ev_5ed670f8628c6d57ca3d31de5bd307ee13b3ea1cdaab51dd0aad6a006be1d330` |
| 版本查询请求构造 | `ev_04f9bc6edef375f40de8a738e52119fd58f9b26e441106f54cb6819dabb41bdc` |

已观察到：常用语新增会进入引擎任务分发，再调用保存；`saveCommonPhraseEdit` 发出任务号 `0x1c`。该包装层没有直接的 HTTP 请求或“手机已确认”回调，因此保存成功不构成云同步证据。

学习词上传控制函数生成 `SyncUploadTaskControl`/`SyncUserDict` 的 protobuf 消息，包含本地学习数据和侧词库数据，保留平台、版本及统计信息；这不是独立的 `POST /word/add`、`DELETE /word` CRUD API。读取的上传控制函数也不足以排除其他同步路径。

`OnLocalUserDictClear` 的本函数体是在账号有效时取消正在执行的任务或清理待执行队列；没有在该函数体里发现远端删除调用。此为限定函数范围的观察，**不是“豆包不存在任何云端删除能力”的结论**。

## 已执行的互操作测试

`common_phrase_probe.cpp` 使用合成词执行：创建空库 → 加入 A → 保存 → 删除 A、加入 B → 保存 → 新实例重新加载 → 核对输入串、解码后的 B 和有效记录数量 → 删除 B → 保存 → 再次加载确认无有效记录。所有断言通过。保存后 A 的旧记录被清理，不能将内存里的 unused 状态推断为持久化云端删除标记。

`learned_probe.cpp` 在空库通过原生 `UsrDict::Add` 新增合成词，保存后原生导出能读到；将频率置零后，该词**仍会被导出**。因此词频清零不应在界面标为“已从豆包删除”。

低层构造实验依赖固定版本的 C++ vtable、对象布局和 libc++ ABI，只适合隔离研究。**不应把这些调用加载进 Squirrel 主进程，不应在未经版本匹配时执行，更不能直接用于实时改写已加载的词库。**

## 同步机制和未解问题

静态分析找到如下内部 HTTP 路径和接口：

```
/api/v2/stream/sync/upload
/api/v2/sync/version
/api/v2/sync/push
/api/v2/sync/pull
```

上传后返回 object_key，push 带 start_version_seq；pull 使用版本序列，再下载与加载文件。请求通过宿主网络接口发送，存在账号状态、MD5、同步类型及版本检查。**没有读取或复用用户令牌，也没有调用这些私有云端端点。** 路径存在不代表已获得可安全复用的对外 API。

`SyncTaskManager::DefaultScheduleIntervalMsLocked` 在 `0x31dd00` 返回 `0x6ddd00`，即 7,200,000 毫秒（两小时）。`OnFinishInput` 另有就绪状态、版本与调度检查；不能断言每次输入结束都会拉取，或者两小时一定能同步成功。

用户已在 iPhone 输入公开测试词“松鼠桥接甲”。随后我通过系统快捷键切到 Mac 豆包，在独立文本编辑文档输入测试串，切回鼠须管，并通过只读 TIS 查询确认恢复。检查的侧词库副本仍未出现该完整词，文件 SHA-256 未变。该结果仅表示**本轮未观察到手机 → Mac 的新词同步**，不能区分手机尚未整词学习、账号不一致、尚未上传、Mac 调度未拉取等原因；更不能声称已通过双向同步。

仍需回答：

1. `saveCommonPhraseEdit` 是否在本机版本触发独立 CommonPhraseDict 同步，还是只做本地保存？
2. 新增学习词怎样经过账号就绪与调度进入上传？可否在不读取令牌、不修改豆包进程的前提下复用？
3. 手机已学词的单项删除如何表达，服务端怎样合并？本地排除列表不能冒充云端删除。
4. 完成一个受控 iPhone → Mac → Rime → Mac → iPhone 的往返，包括新增、修改、删除及重启后不复活。

## 第二轮：实际支持的同步范围

`StartSyncOnSerial` 的已恢复代码与 arm64 汇编交叉核对：只有网络同步类型 **2** 进入上传或版本查询；类型 **1（CommonPhraseDict）** 和 **3（UserDictIncWords）** 进入 `unsupported sync task ignored` 并结束失败任务。汇编位置 `0x314c9c` 比较类型 2，`0x314da4` 起是另外两种类型的名字选择与拒绝分支。对应 REA Evidence 为上表“同步类型的实际执行分支”。

此结论限定于本机这一版引擎的 `SyncTaskManager`，不等于服务端或 iOS 不支持常用语，也不排除宿主其他模块的路径。`CommonPhraseDictPack::Save(bool, ...)` 的函数体只调用本地 `CustomDictBase::Save` 并收集错误，没有云端确认。不能将本地常用语 CRUD 接到界面后宣称它能同步手机。

`OnFinishInput` 先检查账号与当前已加载的拼音词库目录是否就绪，再进行调度。此次反编译也确认其当前时间来自 `time()` × 1000，是 Unix 毫秒；两小时间隔并非每次选词都会立即拉取。账号状态变化函数有清除调度时间和重新调度的分支，但这不构成一个已验证、可对外调用的“立即同步”接口，不应通过清空账号状态或词库强制触发。

`SyncCommonAttr::_InternalSerialize` 写出四个整数型 protobuf 字段；尚未确定四个字段的完整业务语义，不能仅凭没有字段名 `deleted` 就断言没有删除标记。符号表范围内的 `UsrDict` 没有发现任意单词 Remove 入口，Rollback 与“删除指定云端词条”不可混同。云端单词删除、修改及冲突合并仍未得到执行证据。

## iPhone 桌面实查与当前验收结果

用户已解锁 iPhone 镜像。本轮直接查看手机豆包：

- “我的”页面账号昵称与 Mac 设置中的昵称一致；数据同步、个人词库、常用语三个开关均已开启。昵称一致不足以证明底层账号 ID 一致。
- “词库管理”页面只有“个人词库／清空”，点击左侧个人词库未进入逐词列表。**未点击清空。**
- 镜像中新建了独立备忘录；Mac 按键只写入英文测试串，没有手机豆包软键盘候选。该操作不能作为手机端学习事件证据。
- 用户随后在实体 iPhone 上确认“松鼠桥接甲”已经整词选出，长按候选没有单词删除入口。这补足了此前“仅发送文字”的测试条件。
- Mac 的侧词库快照仍是原来的 438,378 字节和 SHA-256；当前未观察到新测试词的云端拉取。切换回鼠须管后，通过持久化输入源记录核对为 Squirrel.Hans；没有修改系统输入源列表。

当前验收状态：手机整词学习已确认；手机 → Mac 新词到达尚未确认；Mac → 手机、单词修改／删除、删除后不复活均未通过。**尚未接入生产界面的双向云端编辑。**

### 第三轮：手机到 Mac 已通过，Mac 到云端已通过

以下结果取代上一段的阶段性验收状态：

1. 用户在 Mac 豆包完成一次真实中文选词并切回鼠须管后，下载版本从 `1792426140000` 推进到 `1792463727000`，侧词库从 438,378 字节变为 439,614 字节。离线原生遍历得到 6,888 个键、9,160 条记录，并找到了完整测试词“松鼠桥接甲”。**手机 → 云端 → Mac 新词到达通过。**
2. 临时将 Mac 豆包从 86 五笔改为拼音；用户帮助切到中文状态后，自动化在同一组字内依次选“松鼠”“桥接”“乙”，完成“松鼠桥接乙”。重新输入完整拼音后，Mac 第一候选即为该词。随后已恢复 86 五笔和 Shift 中英文切换设置。
3. 本地学习词库经异步保存后出现 `usr.dat`。新增 `learned_snapshot_probe.cpp`，在隔离副本中调用原生 Load(false)/Export，确认库中只有 1 条本地学习记录，包含“松鼠桥接乙”；手机词“松鼠桥接甲”则来自侧词库，不在这份本地学习库中。没有为了测试直接改写真实词库。
4. 手机端第一次查询 `songshuqiaojieyi` 时，用户确认没有“松鼠桥接乙”这个完整候选，记录为上传前基线。
5. 正常运行期间，Mac 同步版本仍停留于上一轮，不能以候选已学会宣称已上传。先将 11 个词库文件备份到 Git 忽略的研究目录（合计 1,490,142 字节，目录 0700、文件 0600），再通过活动监视器按已核对的 PID 选择豆包主进程，点击**正常退出**；没有强制退出、退出账号、重装或更改输入源启用列表。通过桌面工具正常启动原安装路径的豆包，确认出现新的主进程。
6. 正常启动后下载版本推进为 `1792464433000`，文件 439,677 字节，SHA-256 为 `eb602949fd8e6fabe0a830e43b6da98f3195e2cd88f494d6294f86045ad8af26`。原生遍历得到 6,889 个键、9,161 条记录，两个测试词都存在，并新增平台掩码 2（此前只有掩码 1）。**Mac 学习词经豆包正常流程上传、服务端合并、重新下发到 Mac 的闭环通过。**这仍不能代替 iPhone 收到该词的验收。

已再次请用户在 iPhone 重新打开豆包 App 后查询完整测试词。iPhone 镜像当时显示“iPhone 使用中”，因此没有强行断开用户的手机操作。当前手机端反向到达结果待确认；云端修改、单词删除、删除后不复活仍未通过，尚未接入生产界面的双向编辑。

本轮词库文件句柄检查的两次额外执行审批均超时；未绕过审批，改用词库目录只读元数据及沙箱副本原生导出定位保存结果。该检查已不再是继续分析的依赖。

### 删除机制的新实验：词频清零不会生成“删除请求”

扩展 `learned_probe.cpp`，先使用原生 `PinyinToSyllableId` 映射真正的中文音节，验证“松鼠桥接乙”的新增／保存／新实例重载／导出。随后在另一个**合成空库**中，仅加入该词，设置本机设备类型，再调用原生 `GenUploadTaskControlPbStream`；有词频时控制流为 94 字节，词频设为 0 后控制流为 0 字节。

这说明：对于仅含这一词的合成库，清零会让原生上传生成器省略该词，且不生成控制流；不会自动产生一个独立的云端删除操作。因此不能把前轮“零频词仍可导出”或本轮“上传中省略”单独当作云端删除成功证据。**非空 FULL 快照中省略单词是否有服务端删除语义仍需另行执行验证；不能从空控制流实验推断所有 FULL 快照的合并策略。**

以上测试均通过离线沙箱运行，没有发送合成控制流，也没有将真实用户词库交给实验上传器。

### 第四轮：手机反向到达仍未通过，桌面跨平台筛选已验证

用户在 Mac 上传确认后重新打开 iPhone 豆包 App，查询完整拼音，仍没有“松鼠桥接乙”整词候选。随后通过已授权的 iPhone 镜像检查“我的”：原账号仍登录，数据同步、个人词库、常用语均为开启。只将“个人词库”开关关闭再开启，最终确认恢复开启；没有点击清空或退出账号。用户在实体手机再次查询，仍无整词候选。

因此，不能将 App 重开或这个开关视为已验证的“立即拉取”。目前无法仅由候选缺失区分手机未下载、键盘扩展未重新加载、词条筛选或排名问题。镜像使用 Mac 硬件键盘，无法替代实体手机的豆包软键盘候选验收。

为核对跨平台限制，使用 REA 分析桌面引擎的 `FindPreferredPlatformWordByKeyValue`（`0x1afd44`）、`SearchCb`（`0x1aff4c`）及 `ForEachUsrSideDictItem`（`0x1abf14`），会话已关闭。Evidence 分别为：

- `ev_a99a573ca76095fc8d4d59b6a433bc8da0e2323a7b4ad3fb1fa8fae94e5589a4`
- `ev_eb3ca7c9ad9f91c27563a4336a9684624498d218845edab1cd9af5bf22fb68bc`
- `ev_564111c65d569909fffb7839d13d1b3bb7a7a85bfe478352367f5637e1ad1f40`

扩展只读 `side_probe.cpp`：仅对两个公开测试词保留其音节键和原生输入串，在隔离副本内设置设备类型 1、2，分别调用原生 preferred 查询。结果为：

| 公开测试词 | 侧词库平台掩码 | 设备类型 1 查询 | 设备类型 2 查询 |
| --- | --- | --- | --- |
| 松鼠桥接甲 | 1 | true | true |
| 松鼠桥接乙 | 2 | true | true |

这验证了**当前 Mac 二进制**对两种来源词条具有跨平台查询结果，排除了“此桌面函数直接拒绝另一平台记录”的解释。它不等于 iOS 实际二进制行为，也不验证完整候选排序、手机文件内容或手机端拉取成功。侧词库仍为第三轮 439,677 字节和相同 SHA-256。未改真实词库，也未接入未验证的云端修改／删除按钮。

设备类型设置后又调用 `GetDeviceType` 读回，确认确实分别为 1、2；不将无效 setter 的结果误记为跨平台验证。只读 CoreDevice 检查确认已配对 iPhone 可连接，手机豆包输入法版本为 **1.6.1（1060105）**。列出该应用数据容器根目录时，系统返回 `CoreDevice.ActionError 3 / failed to get a list of files`，没有取得手机词库。未尝试绕过隔离、读取登录令牌、越狱或更改手机安全设置；此错误本身不能确定是应用容器访问限制、设备锁定状态还是其他设备服务问题。

用户又在实体手机完成普通词选词上屏、切到系统键盘再切回豆包后查询，仍没有完整“松鼠桥接乙”。这排除了这两种简单触发方式能立即使词条出现；不据此声称手机永久不支持电脑词。

另通过 macOS 控制台连接同一已配对 iPhone，短时查看设备统一日志。能观察到豆包键盘扩展相关的运行活动，但本轮 `KeyboardExtension` 进程加 `SyncUsrDict` 消息筛选没有结果，没有得到能确认词库版本、下载或合并的消息。仅凭没有此日志不能证明没有同步请求；厂商可能未将这些内部日志接到系统统一日志。采集已暂停，控制台已退出，没有保存设备完整日志，也没有长期开启诊断。

[官方 App Store 版本历史](https://apps.apple.com/cn/app/%E8%B1%86%E5%8C%85%E8%BE%93%E5%85%A5%E6%B3%95-%E8%B1%86%E5%8C%85%E5%90%8C%E6%AC%BE%E8%AF%AD%E9%9F%B3%E8%BE%93%E5%85%A5/id6752316550?platform=ipad) 本次查询列出 1.6.1；1.5.0 引入账号及词库定时云端同步，1.5.6 另引入常用语多端同步。该描述不能确定手机同步间隔、私有 API、Mac 平台词条的合并策略或单词删除机制。未找到可代替实际往返验收的公开接口说明。

**截至本轮：手机 → Mac 已通过，Mac → 云端 → Mac 已通过，Mac → iPhone 未通过；云端单词修改／删除及删除后不复活未通过。生产词库管理界面的双向云端编辑尚未实现。** 继续定位需要取得一次手机端实际拉取的版本／结果证据，目前现有文件读取与这段系统日志不足以提供它。

## 只读同步状态诊断

新增 `tools/doubao_sync_state.py`，只解码匹配版本的 `SyncLocalTaskState`。字段映射依据原生 `SyncTaskStateStore::Save`（`0x321b78`）与已恢复的账号加载、输入结束函数交叉核对。它读取本地状态，不发请求、不加载厂商代码、不改文件，也不返回账号 ID、词库路径、个人词条或密钥。

```sh
python3 rime/tools/research_doubao_dictionary.py status
python3 -m unittest discover -s rime/tools/tests -p test_doubao_sync_state.py
```

本轮状态记录的调度时间为 2026-10-20 00:09:00（北京时间），上传检查点为前一秒，下载版本序列为 `1792426140000`。状态中的词库目录匹配当前唯一账号目录。下载文件大小记录为 438,378 字节，但保存的下载 MD5 与当前侧词库文件 MD5 不同；这可能涉及下载产物到本地侧词库的转换／重写，**仅凭不同不能判定下载失败，也不能声称已验证文件传输完整性**。诊断明确输出 `sideMatchesStoredDownloadMD5`，不把它当作词条同步成功标志。

解析器对过大、截断、溢出 varint、重复字段、未知 schema／wire type 关闭解析；4 项合成测试通过，覆盖隐私字段不输出、目录不匹配、哈希不匹配及损坏数据。多账号有歧义时拒绝猜测。研究助手的离线沙箱限制继续保留；本轮桌面只读输入源查询的额外执行审批两次超时，没有绕过审批或关闭隔离重试。

## 重复验证

在仓库根目录运行：

```sh
python3 rime/tools/research_doubao_dictionary.py inspect
python3 rime/tools/research_doubao_dictionary.py selftest
```

需要 macOS arm64、Xcode 命令行工具及上面匹配哈希的豆包引擎。工具只编译自己的研究助手；默认只输出数量、快照哈希和公开测试词是否存在。每轮使用权限 0700 的临时目录，完成后清除副本。助手被 sandbox-exec 禁止联网、禁止读取真实豆包数据目录、禁止写入工作目录外位置。在 Codex 的外层受限环境里创建嵌套沙箱可能需要执行授权；拒绝时应停止，不取消沙箱重试。

`inspect --export /明确的新文件路径` 才保留原生明文导出，文件权限 0600，目标已存在时拒绝覆盖。该文件是私人数据，不进入 Git、安装包、日志或火山 ASR 热词。

## 管理界面接入约束

未来界面需要显示词条来源（本地自定义／豆包学习词／豆包常用语）、独立读音、同步方向及待同步/本地已保存/远端已确认/失败状态。Rime 编码不直接当作豆包拼音；用户自定义混合格式不被自动学习结果覆盖。手机学习词不默认勾选 ASR 热词；现有 dotfiles 自定义词典保留。

只有完成上述往返测试，才启用明确的“同步到豆包”成功状态。当前没有安装新版本，也没有把未验证的云端编辑按钮加入词库界面。

公开参考：[官方账号与词库同步更新记录](https://apps.apple.com/cn/app/id6752316550)、[ime-lexicon 旧版文件格式](https://github.com/taxueseek/ime-lexicon/blob/main/skill/references/formats.md)。本轮新版本地接口结论来自本机二进制和隔离互操作实验，并非旧项目宣称。

## 第五轮：Mac → iPhone 推送方向调研（2026-10-20）

### 结论

**Mac → iPhone 用户词库同步已验证可用，但是按调度最终一致的，不是即时推送。** 2026-10-20 的受控测试中，Mac 学习的公开测试词“松鼠桥接乙”在约两小时后出现在 iPhone 豆包键盘的第二候选；期间用户在 iPhone 上切换过“数据同步”开关。此前“未观察到”的结论来自测试时间窗过短，不能据此判定平台过滤。

因此不需要逆向私有同步接口：把 Rime 词写入 Mac 豆包的本地学习词库，让豆包自己的引擎按正常流程上传即可。官方文案只承诺“手机输入或纠正过的词会出现在电脑端候选”，没有描述反向延迟；实测证明反向也会到达，只是要等 Mac 上传调度和 iPhone 拉取调度各一次。

### 实测补充：约两小时后 iPhone 收到

- 测试词：“松鼠桥接乙”（此前在 Mac 豆包学习，侧词库平台掩码 2）。
- 操作：iPhone 豆包“我的”里关闭再打开“数据同步”，之后正常使用手机。
- 结果：约两小时后，用豆包键盘输入完整拼音，该词出现在**第二候选**。
- 结论：iPhone 会消费 PC 平台词；之前的候选缺失是同步尚未完成，不是平台过滤。后续实现不需要伪造 MOBILE 平台控制流。

### 本轮新增证据

1. **上传控制流的平台字段**
   - 使用引擎符号 `GenUploadTaskControlPbStream` 对合成 `UsrDict` 生成上传流：`SetDeviceType(1)` 时首字段为 1，`SetDeviceType(2)` 时为 2，其余字段相同。
   - wire 解码结构：`SyncUploadTaskControl.field 1 = device_type`，`field 2 = repeated SyncUserDictPackage`；每个 package 含类型/统计/词条；词条 oneof 的字段 100 对应 `pinyin_user_word`，内含 packed 音节 ID、输入串和 packed UTF-16 词语。
   - 传入真实侧词库副本时，payload 只增加 29 字节的 `SyncUserSideDictInfo` 元数据，不包含侧词库词条。**侧词库不是上传载体。**
   - 引擎枚举 `SyncUserDictDeviceType` 为 `MOBILE / PC / UNSPECIFIED`；`SyncUserDictPlatform` 另有 `IOS / ANDROID / DARWIN / ...`。本机侧词库掩码 1/2 与设备类型一致。

2. **平台掩码与公开测试词**
   - 侧词库 9,161 条记录，掩码仅 1、2；“松鼠桥接甲”掩码 1（手机学习），“松鼠桥接乙”掩码 2（Mac 学习）。
   - `FindPreferredPlatformWordByKeyValue` 在 Mac 引擎内对设备类型 1 和 2 都返回 true，说明 Mac 端可以跨平台查询；本轮没有证据表明 iOS 端同样放行。
   - Mac 引擎包含 `OtherPlatformSideUsrCandContext`、`same_platform_side_dict_*`、`other_platform_side_dict_*` 等逻辑。这解释了 Mac 能显示手机词，但不能反推 iPhone 会显示 Mac 词。

3. **宿主和界面**
   - Mac 设置应用只有 `keyboard`、`voice`、`about` 三个 tab（`--openTab` 字符串）；没有词库管理或导入页。
   - Mac 账号目录的 `common_phrase_dict.dat` 为 44,088 字节，原生只读加载得到 **0 条常用语**；`SyncTaskManager` 对同步类型 1（CommonPhraseDict）和 3（UserDictIncWords）直接拒绝，只有类型 2 进入上传/版本检查。常用语不能作为 Mac → 手机的桥。
   - iPhone 端公开资料和实查均没有手动导入或逐词编辑入口；“词库管理”只有个人词库/清空。

4. **官方能力边界**
   - App Store 版本历史与官方宣传只描述“手机输入/纠正过的词会出现在电脑端候选”，未承诺电脑 → 手机。
   - 第三方 Windows 工具“豆包输入法词库导入工具”只写本机 `%APPDATA%\DoubaoIme\dict\usr.dat`，帖子明确说“全程不需要联网”，没有跨设备同步能力。

5. **手机取证的限制**
   - `devicectl`、AFC、House Arrest 对 App Store 应用的容器返回 `ContainerLookupError 3` / `InstallationLookupFailed`。
   - MobileBackup2 的 `--only-regex` 是落盘过滤，设备仍会枚举全机文件；首次 6 分钟到 12%，第二次因锁屏密码提示被忽略停在 0%。部分备份已删除。
   - 未读取账号 token，未修改手机数据。

### 本地可做的部分

`UsrDict::Load/Add/Save` 已在隔离副本验证；`Add` 使用 `PinyinToSyllableId` 映射真实拼音音节。上传控制流的时间戳/词频来自词条属性，`GenUploadTaskControlPbStream` 的 checkpoint 会跳过旧词。因此 **Rime → Mac 豆包 `usr.dat`** 技术上可行，且可备份/回滚；但它只改变 Mac 端候选，默认按 PC 平台上传。

实现时还需要把 Rime 词条转成豆包拼音输入串：

- 若 Rime 词库本身带拼音编码，可直接用；
- 若只有五笔或自定义编码，需要中文 → 拼音转换（系统 `CFStringTransform` 或 Rime 拼音词典），再逐音节调用 `PinyinToSyllableId`；
- 多音字、儿化、分词和 Rime 混合格式要保留人工校对，不能把五笔编码当拼音。

### 可选路线

A. **Mac 本地注入（推荐）**：读 Rime 用户词典 → 生成拼音 → 备份并写入 Mac 豆包 `usr.dat` → 重启豆包，让引擎正常上传。实测手机在同账号下一次调度后可见（约两小时）；这是不使用私有接口的唯一完整路线。
B. **私有同步 API（不推荐默认启用）**：用账号 token 和引擎生成的 `device_type=MOBILE` 控制流，走 `/api/v2/stream/sync/upload` → `/api/v2/sync/push`。这是唯一可能强制 iPhone 接收 Mac 词的路线，但属于逆向私有接口；token 位于 `~/Library/Application Support/DoubaoIme/.tt.account.sdk/`，读取和复用涉及账号安全，版本升级可能失效，且可能违反服务条款。未获明确授权前不实施。
C. **手机端替代**：改用支持 Rime 用户词典导入的手机键盘（同文输入法/仓输入法/Hamster），或继续在 iPhone 豆包上通过实际选词让词库学习。若目标是“Rime 词在手机可用”，这条路线比逆向豆包更稳。

### 已验证结果与下一步

2026-10-20 的手机实测已完成：iPhone 豆包关闭再打开“数据同步”并等待约两小时后，“松鼠桥接乙”出现在第二候选。**Mac → iPhone 链路验收通过，路线 A 成立。**

下一步实现“Rime 用户词典 → Mac 豆包 `usr.dat`”的导入器，并在写入后触发豆包的正常同步。实现需要解决：

1. Rime 用户词典来源：`custom_phrase.txt`（自定义短语，带拼音编码）、`rime_frost.userdb`（拼音学习词，966 条）、`wubi86.userdb`（五笔学习词，9,563 条，编码不是拼音）。
2. 中文 → 拼音：优先使用 Rime 拼音词库里的编码；五笔来源用 `CFStringTransform` 或 Rime 拼音词典转换，多音字需人工校对。
3. 安全写入：先写 `usr.dat` 的隔离副本并用原生 `Load/Add/Save` 校验，再备份并原子替换真实文件；引擎 SHA-256 不匹配时拒绝。
4. 同步预期：写入并重启豆包后，Mac 端按正常调度上传，iPhone 端最长约两小时出现；不做私有 API、不读取账号 token。
5. 验收测试：先用公开测试词“松鼠桥接丁”（`songshuqiaojieding`）走完整链路，确认 Mac 候选、上传版本推进、iPhone 候选，再导入真实词库。

新增研究代码（均只读或仅操作合成词库）：`native/doubao-dictionary/upload_probe.cpp`、`common_phrase_snapshot.cpp`。本轮没有修改真实豆包 `usr.dat`、侧词库、账号目录或手机数据。

### 实现状态（2026-10-20，第一版）

已实现“推送到豆包…”UI 与外部 helper：

- `native/doubao-dictionary/doubao_push.cpp`：预览/写入 Mac 豆包 `usr.dat`；固定引擎 SHA-256；自动选择唯一账号；预览在临时副本上执行 Add，不写真实文件；apply 备份、校验、原子替换；`--selftest` 使用合成词库。
- `tools/build_doubao_push.sh`：编译、ad-hoc 签名、selftest、安装到 `~/Library/Application Support/Squirrel/DoubaoPush/doubao_push`。不进入 Squirrel.app/PKG，不改变发布签名策略。
- `native/voice/DoubaoDictionaryPush.swift` + `VoiceDictionary.swift`：用户词典窗口“推送到豆包…”按钮、预览表（词/拼音/来源/状态）、二次确认、退出豆包、写入后提示。
- `tests/doubao_push_test.swift`：过滤、去重、TSV、预览/结果解析、错误映射，以及从 Swift `Process` 调用 helper 的 `--version`/`--preview`。

本轮实测补充：

- `UsrDict::Add` 对相同 `(音节向量, 输入串, 词)` 幂等（count 不变）；同输入串下不同词 count +1。去重因此使用 count delta，不依赖导出格式解析。
- 真实自定义短语只读 preview：第一版按汉字过滤时为 17 行可添加、19 行纯英文/邮箱跳过；后续实测 `UsrDict::Add` 可把 `yangyu445`、`yangyu445@jd.com` 挂到 `yang yu` 并 Save/Reload/Export，已移除 UI/helper 的纯 ASCII/邮箱过滤，重建签名包。`im.shenshen@qq.com` 的 `mem` 编码不是拼音，会标记失败。
- helper selftest：首次 apply 新增 8 条，第二次 apply 新增 0 条；`GenUploadTaskControlPbStream` 非空且包含测试词输入串。
- `bash rime/tools/test_voice_preferences.sh` 通过；Squirrel app 已编译、Developer ID 签名、公证和装订通过。
- 用户从签名 PKG 完成安装后，通过“用户词典 → 推送到豆包…”只推送公开测试词“松鼠桥接丁”。面板报告写入 1 条，备份为 `~/Library/Application Support/Squirrel/DoubaoPush/backups/usr.dat.bak-20261020-222435-17763`。
- 写入后只读核验：helper preview 对该词返回 `exists`；`localLearnedRecords` 从 1 变为 2；`inspect` 的侧词库副本为 444,843 字节，包含“松鼠桥接丁”且平台掩码为 2（Mac 来源）；同步状态推进为 `1792506325000`，上传检查点和下载版本一致。说明 **Rime 自定义短语 → Mac 豆包本地学习库 → 豆包云端合并 → Mac 侧词库** 链路已通过。
- 用户在 iPhone 豆包键盘输入 `songshuqiaojieding`，已确认“松鼠桥接丁”出现在候选中；**Rime 自定义短语 → Mac 豆包 → 云端 → iPhone 完整链路通过**。同期手机输入 `yangyu` 已出现汉字词“杨宇”，但纯 ASCII 的 `yangyu445` 因第一版过滤未推送；ASCII/邮箱支持已补齐，待用户从新包推送后复测。

已知边界：第一版只推 `custom_phrase.txt`；Rime userdb（拼音/五笔学习词）未接入。Mac 豆包当前为 86 五笔模式，新词是拼音学习词，Mac 端不一定立即显示，最终以 iPhone 候选验收。恢复 Mac 本地备份不会删除已上传的云端词。豆包引擎升级后 helper 会拒绝写入，需要重新构建。
