# 云候选与五笔/拼音混输

云候选由 `native/cloud_pinyin/cloud_pinyin.mm` 实现，随定制 Squirrel 编译，不在 Lua 按键回调里做网络 I/O。前端只通过 `native/squirrel/cloud-badge.patch` 加入的 `_refresh_ui` 协议刷新候选和角标。

## 本地混输规则

- `wubi86.custom.yaml` 恢复第五码顶字：前四码同时生成五笔和拼音候选，五笔排在普通拼音前，自定义词优先。
- 输入四个小写字母、光标在末尾、未分段/手动选词、首选覆盖完整五笔编码，且本地拼音没有覆盖整段的候选时，下一码提交五笔首选并保留为下一组编码。`ggllg` → “一” + `g`；`jjjjj` → “日” + `j`。
- 有拼音候选时保留整串；`aaaa` 等同时是五笔和拼音的编码保守地不顶字。
- `wubi86_pinyin.schema.yaml` 为白霜词典生成独立正常拼音音节索引，支持末音节补全；不启用首字母简拼，避免 `g g l l` 阻止顶字。
- `lua/wubi_pinyin_router.lua` 修改分段标签；`mixed_pinyin_translator` 继承原生拼音翻译器并记录候选覆盖范围。拼音写入独立的 `wubi86_smart_pinyin` 用户词典，不混入五笔词库。
- 单个 `z` 是正常拼音；`zhongguo` 查“中国”。显式反查前缀为 `zz`，例如 `zzni`、`zznihao`；云服务收到去掉 `zz` 的编码。分号/单引号保留第二/第三候选快捷键。
- 五笔连打造句默认关闭；`wubi_mixed/fifth_code_auto_commit: false` 可关闭顶字而保留混输。

## 排序、缓存和刷新

- 自定义词优先，然后按配置的服务顺序逐轮交错：本地第 1、搜狗第 1、Google 第 1、本地第 2、搜狗第 2、Google 第 2……重复文字保留首次出现项，缺失来源跳过。
- 云候选与本地候选文字相同时，保留原生候选对象及学习能力；UI 只显示一个浅色云图标，不显示服务名。来源位掩码通过隐藏字符传给前端，保留原有五笔注释。
- 选中的纯云词写入独立 `wubi86_cloud_history.userdb`，后续作为本地候选；5 分钟缓存只用于避免重复请求。
- 缓存按服务、原始拼音、候选数量、适配器版本区分；显式音节边界保留（`xian` ≠ `xi'an`）。缓存只存完整匹配的候选文字和服务键，不存 Rime Candidate/位置。
- 同一键的在途请求合并；删改后的旧响应可进缓存，但只有会话、请求版本、当前输入、光标和活动分段都一致时才刷新界面。
- TTL 从成功完成时用单调时钟计算，读取不续期；失败按服务退避 2/4/8/16/32 秒，其他来源继续。
- 用户已移动高亮/翻页/选字时冻结候选位置；迟到结果先写缓存，下次安全更新再展示。
- 先显示本地/缓存，再异步请求；搜狗返回即可补候选，不等待 Google。

默认参数：

| 参数 | 默认 |
|---|---|
| 搜狗 | 开启，排在 Google 前，超时 800 ms |
| Google | 开启，超时 1500 ms |
| 百度 | 关闭，保留适配器 |
| 停输入后查询 | 150 ms |
| 每来源候选上限 | 5 |
| 成功缓存 TTL | 5 分钟 |
| 空结果缓存 | 15 秒 |
| 缓存容量 | 256 条 LRU |

方案菜单有“本地 / 云候选”开关，默认开启。`wubi86.custom.yaml` 的 `cloud_pinyin/providers` 可开关/排序；关闭云候选不影响本地词库和已学习云词。四码以内五笔和英文模式不联网。

## 隐私与网络

- 每次只发送当前未确认拼音段，不发送已上屏文字或应用内容；启用多家时分别发送。
- 仅 HTTPS，回退 HTTP 被禁止；无 Cookie/持久缓存，响应有大小和超时限制。
- 云服务是消费端/开源适配器，不承诺稳定 API、配额或 SLA。百度适配器保留但默认关闭；Google 的旧 Transliterate API 与当前 Input Tools 不是同一产品。
- 已知风险：云服务重定向域名未完全收紧、依赖上游 plum 资源的可复现性、安全输入边界。修改网络/隐私逻辑前先审查代码并补测试。

## Squirrel 刷新边界

稳定版 Squirrel 1.1.2 没有 `_refresh_ui`；本项目固定上游提交 `0cd71a6130a5866b0ae6ba0494929ebdc8211194` 已包含该协议。插件必须先在主队列更新缓存、让引擎重新生成候选，再通知前端；后台线程不能直接调用 Lua/修改 Rime Context。

## 验证

```sh
bash rime/tools/test_cloud_core.sh
python3 rime/tests/verify_local.py /tmp/rime-wubi-smart-test
python3 rime/tests/verify_mixed.py /tmp/rime-wubi-smart-test
RIME_CLOUD_TESTING=1 bash rime/tools/build_cloud_plugin.sh
python3 rime/tests/verify_cloud.py
python3 rime/tests/verify_cloud_live.py
python3 rime/tools/probe_cloud.py --providers sogou google baidu
```

`cloud_core_test.cc` 验证交错、去重、缓存键、TTL、LRU、二进制边界；`verify_local/mixed` 使用隔离 `/tmp` 用户目录；`verify_cloud` 需要测试版插件；`verify_cloud_live` 和 `probe_cloud` 只发公开样例、需要真实网络。测试目录必须在临时目录，不能打开日常用户词库。
