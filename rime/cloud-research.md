# Rime 云候选接入与缓存设计

五笔第五码顶字、拼音混输和云候选已经接入。macOS 原生插件同时查询搜狗与 Google；百度保留适配器，默认关闭。插件源码在 `native/cloud_pinyin/`，随[源码构建的鼠须管](build-squirrel.md)一起编译、签名和安装。候选面板使用 `native/squirrel/cloud-badge.patch` 的小型显示补丁，不需要维护远端 fork。

## 本地输入规则

2026 年 10 月 13 日起，`wubi86.custom.yaml` 恢复由原生处理器控制的第五码顶字。前四码同时生成五笔和拼音候选，五笔排在普通拼音前，自定义词仍优先。当前整段恰好四个小写字母、光标在末尾、未分段选词或手动切换候选、首选覆盖完整五笔编码，并且本地拼音没有覆盖整段的候选时，下一个字母提交五笔首选并留作下一组编码。`ggllg` 提交“一”并留下 `g`；`jjjjj` 提交“日”并留下 `j`。

有拼音候选时保留整串，第五码起继续原生拼音翻译和云查询。`aaaa` 同时是五笔编码和四个拼音 `a`，因此保守地暂缓顶字。`wubi86_pinyin.schema.yaml` 为白霜词典生成独立的正常拼音音节索引，支持末音节补全，关闭首字母简拼，避免 `g g l l` 这类简拼阻止所有五笔顶字。五笔连打造句仍关闭；可将 `wubi_mixed/fifth_code_auto_commit` 设为 false 并重新部署，关闭顶字而保留混输。

`lua/wubi_pinyin_router.lua` 修改分段标签，`mixed_pinyin_translator` 继承原生拼音翻译器并记录本地候选覆盖范围，保留原生候选及选词学习。拼音使用独立的 `wubi86_smart_pinyin` 用户词典，不混入五笔词库。部分选词后，路由器让剩余编码继续使用拼音，即使剩余部分不足五码。顶字经正常确认和提交通知完成，因此保留五笔学习；拼音索引未成功加载时，处理器不会顶字。

单个 `z` 是正常拼音字母：`zhongguo` 查询完整拼音“中国”，`zhishi` 查询“知识”，不再丢掉首字母。显式反查前缀改为 `zz`，例如 `zzni` 查询短拼音“你”，`zznihao` 查询“你好”；云服务收到的是去掉 `zz` 的编码。分号与单引号仍选第二、第三候选，单引号不能在已有候选时用作拼音分隔符。空格确认候选，Escape 清空。原来的默认英文模式保留。

混输后，日常拼音不需要 `zz`。保留它作为可选的强制反查入口：短拼音与五笔候选竞争时直接使用拼音反查，并通过候选注释查看五笔编码。普通混输与显式反查都保留云候选支持。

## 白霜词库更新判断

2026 年 10 月 13 日查阅上游，近期四次实际增词提交均只修改 `cn_dicts/others.dict.yaml`：[10 月 9 日](https://github.com/gaboolic/rime-frost/commit/dab51f661a43858a23723b1d175eb5aeb4ce65f3)新增 45 条，[10 月 10 日](https://github.com/gaboolic/rime-frost/commit/6cf30265bf0c8015adc3213fe09ef13abbff1589)新增 33 条，[10 月 12 日](https://github.com/gaboolic/rime-frost/commit/b896672189df0b6e85842fd9241697c36c1ef2b8)新增 44 条，[10 月 13 日](https://github.com/gaboolic/rime-frost/commit/d7d86f162d69c5730b46647a4e8cd11a429e08a3)新增 31 条，共 153 条词库项。这些提交补充知乎热榜相关的游戏、科技、人物、历史和专业术语；最新一批包括“宇树”“尊界”“类魂”“推流”。新增项的权重为 0，主要增加可识别范围，不代表默认一定排第一。

继续使用白霜作为本地拼音词库比较合适：混输判定与云候选由本仓库控制，白霜提供词条和词频。词库更新后重新部署即可，无需重新编译鼠须管；升级时应保留本仓库的五笔定制配置、路由 Lua 和正常音节索引方案。上述上游增词尚未应用到本机，本次安装只更新混输插件与配置。

## 候选排序与开关

所有自定义词优先，然后逐轮显示本地第 1 词、搜狗第 1 词、Google 第 1 词、本地第 2 词、搜狗第 2 词、Google 第 2 词，以此类推。重复文字保留最先出现的一项，缺失的来源或名次直接跳过，不显示占位项。哪家先返回就先参与合并，最终顺序按配置中的服务顺序排列。

重复云词若已有覆盖相同编码范围的本地候选，保留原生候选对象及其学习能力。2026 年 10 月 9 日起，云来源改用文字右下方的浅色云图标，不显示 `搜狗云`、`Google 云` 等服务名称；同一候选来自多家也只显示一个图标。原本的五笔编码等注释保留。插件通过隐藏的私有标记传递来源位掩码，前端在排版前剥离标记、追加 12×9 的 SF Symbols `cloud.fill` 图像，不使用云 emoji。

选中的纯云词写入独立 `wubi86_cloud_history.userdb`，之后作为本地候选参与排序；短期缓存只负责避免重复联网，不承担长期学习。云服务可能返回扩展词，例如 `menghuanmonizh` 的搜狗结果包含“梦幻模拟战号”，这是服务返回的候选，不是候选拼接产生的文字。

方案菜单新增“本地 / 云候选”开关，默认开启云候选。修改 `wubi86.custom.yaml` 的 `cloud_pinyin/providers` 可以分别开关每家服务或调整服务顺序，重新部署后生效；关闭云候选不影响本地词库和已学习的云词。四码以内的普通五笔和英文模式不查询网络。

每次只发送当前未确认拼音段，不发送已上屏文字或应用内容。启用多家时这段拼音会分别发给各家。使用 HTTPS、内存缓存和无 Cookie 的临时网络会话，不回退 HTTP。

## 云服务实测

2026 年 10 月 8 日，在本机网络上使用 `tools/probe_cloud.py` 测试五个公开示例拼音。每个输入同时查询三家，每家超时三秒，全部使用 HTTPS。以下是一次小样本结果，不能当作服务整体准确率或延迟保证。

| 服务 | 接入方式 | 五个输入的结果 | 耗时范围 |
| --- | --- | --- | --- |
| 搜狗 | `https://shouji.sogou.com/web_ime/mobile.php`，POST 二进制数据，UTF 16 LE 候选 | 5 次均成功；“新质生产力”“黑神话悟空”“大模型”均为首选 | 57–109 毫秒 |
| Google Input Tools | `https://inputtools.google.com/request`，GET，JSON，`itc=zh-t-i0-pinyin` | 5 次均返回候选；“新质生产力”首选为“心知生产力”，其他示例首选正确 | 521–728 毫秒 |
| 百度 olime | `https://olime.baidu.com/py`，GET，JSON | 5 次均返回失败；复核为 `status=F`、`errno=19`、`errmsg=Internal Error` | 41–138 毫秒，均为失败响应 |

| 输入 | 搜狗首选 | Google 首选 |
| --- | --- | --- |
| nihao | 你好 | 你好 |
| rengongzhineng | 人工智能 | 人工智能 |
| xinzhishengchanli | 新质生产力 | 心知生产力 |
| heishenhuawukong | 黑神话悟空 | 黑神话悟空 |
| damoxing | 大模型 | 大模型 |

搜狗的社区实现原先使用 HTTP，本次实测同一接口的 HTTPS 版本可以返回有效二进制候选。应采用 HTTPS，不因失败回退到 HTTP。Google 可作为独立补充源，但需要在用户实际网络上验证连接速度。百度当前测试失败不等于永久不可用，后续若修复适配器或接口恢复，可单独启用。

这些方式来自消费端输入工具及开源适配器，不应当作拥有稳定接口契约、配额承诺和 SLA 的商业 API。没有在此次调研中确认当前有效的三家拼音候选商业 API。Google 曾经的开发者 Transliterate API 文档已标为 Deprecated；它与当前 Input Tools 网页接口及 Cloud Translation 不是同一个产品。

来源：[Google 适配器](https://github.com/hchunhui/librime-cloud/blob/master/scripts/lua/google.lua)、[百度适配器](https://github.com/hchunhui/librime-cloud/blob/master/scripts/lua/baidu.lua)、[搜狗二进制协议](https://github.com/hchunhui/librime-cloud/blob/master/scripts/lua/sougou.lua)、[Google Input Tools 支持语言](https://www.google.com/inputtools/help/languages.html)、[已弃用的 Transliterate API](https://developers.google.com/transliterate/v1/reference)。

## 多家并行查询

查询由原生插件的 `NSURLSession` 异步执行，Lua 只做输入分段路由。插件在主队列更新缓存和 Rime 引擎，不在逐键回调里等待网络，也不需要额外启动 Python 后台服务。

每家拥有独立开关和超时，可同时启用。当前默认配置如下：

| 参数 | 当前默认值 |
| --- | --- |
| 搜狗 | 开启，每轮排在 Google 前，单次超时 800 毫秒 |
| Google | 同时开启，单次超时 1500 毫秒 |
| 百度 | 关闭，保留独立适配器 |
| 输入停止后查询 | 150 毫秒 |
| 每家候选上限 | 5 个 |
| 成功结果缓存 | 5 分钟 |
| 成功响应但没有候选 | 15 秒 |
| 缓存总容量 | 256 条，按最近使用顺序淘汰 |

先立即显示本地候选和缓存命中项，再并行发出缓存未命中的请求。搜狗返回即可补充候选，不等待 Google。服务之间的评分不直接比较，按上面的轮流顺序及各家内部排名合并。

用户尚未移动候选高亮时，可以更新排序；用户已经选择候选、翻页或移动高亮时，冻结当前候选位置，避免正在按数字选字时候选换位。迟到结果先写缓存，等下一次安全的输入更新时再展示。

## 编辑和删除时的缓存

按每家服务分别缓存。键包含服务名、原始拼音、候选数量和适配器版本；目前语言固定为中文拼音。缓存不以会话或请求序号作为键，因此删除字符后又输入相同内容可以复用结果。拼音中的显式音节边界必须保留，例如 `xian` 与 `xi'an` 不能盲目合并。

缓存只保存已经验证为完整匹配的候选文字、服务键和到期时间，不保存带有 segment 起止位置的 Rime Candidate。展示时按当前分段重新构造候选，避免编辑后的旧位置错配。搜狗根据响应内的音节结束位置校验覆盖长度，Google 与百度按响应的匹配长度校验。搜狗暂不查询包含显式单引号边界的编码，Google 保留原始边界。

例如输入 `nihaoshijie` 后删除为 `nihao`，两者是不同的缓存项。重新输入 `nihaoshijie` 时直接命中已有结果。不能把较长输入的候选截成较短输入的候选，也不能假定“你好世界”一定适用于 `nihao`。

同一服务和缓存键的在途请求合并。用户删改后，旧请求即使完成也可以进入短期缓存，但只有会话、请求版本、当前原始输入、光标和活动分段均与发起时一致时，才能刷新当前候选。缓存结果可复用不代表旧请求可以直接更新界面。

TTL 从请求成功完成时开始计算，使用单调时钟；读取缓存不延长新鲜度。断网和解析错误不当作空候选成功结果，按服务分别退避 2、4、8、16、32 秒，其他来源继续工作。内存缓存进程退出即清空；用户明确选中的云词进入独立的长期本地词库，不依赖这五分钟缓存。

## Squirrel 异步刷新

官方稳定版 Squirrel 1.1.2 的通知处理代码没有 `_refresh_ui` 协议。上游主分支已经有此协议，且在主线程处理通知并校验会话。本机已编译上游提交 `0cd71a6130a5866b0ae6ba0494929ebdc8211194`，安装和验证方法见[编译文档](build-squirrel.md)。该提交的版本字符串仍为 1.1.2，应通过 `LocalBuild.plist` 区分源码构建。云查询落地使用这个入口，无需维护自己的前端 fork。[稳定版通知处理](https://github.com/rime/squirrel/blob/1.1.2/sources/SquirrelApplicationDelegate.swift)、[上游协议](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/ReservedProperty.swift)、[上游刷新实现](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/SquirrelInputController.swift)。

`_refresh_ui` 仅刷新界面；插件仍要先安全更新缓存、让引擎重新生成候选，然后再通知前端。后台线程不能直接调用 Lua 上下文或任意修改 Rime Context。

## 验证方式

`tests/verify_local.py` 使用本机 Squirrel 的实际 librime 和 Lua 插件，只允许打开临时目录中的已部署配置。先将 Rime 源配置、词典和 build 文件复制到临时目录，覆盖本次配置及 Lua 文件，再用 `rime_deployer --build` 编译，最后运行：

```sh
python3 rime/tests/verify_local.py /tmp/rime-wubi-smart-test
```

检查拼音保护、退格回四码混输、部分选词后的短拼音、光标编辑、完整的 `z` 开头拼音、`zz` 反查、表情标点及 Escape 清空。`verify_mixed.py` 另外验证第五码顶字、连续两组五笔、下一个字母保留和歧义编码保护，使用相同临时目录并显式传入应用及插件路径。两个脚本明确关闭云开关，不发送网络请求。

云插件测试分三层：`cloud_core_test.cc` 验证交错顺序、去重、缓存键、TTL、LRU 和二进制边界；`verify_cloud.py` 使用仅测试构建中存在的模拟响应，验证真实 Rime 的异步刷新、迟到响应、冻结菜单、跨会话请求合并、失败退避、开关切换和离线学习；`verify_cloud_live.py` 只用公开样例验证生产插件的真实 HTTPS 查询和刷新。测试目录必须位于临时目录，不能打开日常用户词库。

从仓库根目录通过 `RIME_CLOUD_TESTING=1 bash rime/tools/build_cloud_plugin.sh` 构建测试版，文件名为 `librime-cloud-pinyin-test.dylib`；正常打包只复制 `librime-cloud-pinyin.dylib`，不会安装模拟响应入口。

云接口探测脚本不会读取输入法数据，默认只发送上述公开示例。可以用 `--providers` 同时选择多家，输出每家响应、候选和耗时：

```sh
python3 rime/tools/probe_cloud.py --providers sogou google baidu
```

脚本是独立调研工具，内部等待网络的操作不应直接移入输入法的 Lua 按键回调。
