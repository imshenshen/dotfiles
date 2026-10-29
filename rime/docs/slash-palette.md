# 符号与 GIF 大面板（`/fh` / `/gif`）

中文模式下，`` ` ``、`#`、`%`、`*` 直接输入 ASCII，不弹出候选。`/fh` 打开可搜索的分类符号面板；`/gif` 打开同一非激活大面板搜索在线 GIF。普通 `/`、`/bq`、`/mac` 和其他 Rime `/xx` 类别保持原行为。

## 直接 ASCII

`wubi86.custom.yaml`、`rime_frost.custom.yaml`、`luna_pinyin_simp.custom.yaml` 都保留半/全角标量补丁，并注册 `lua_processor@*slash_literal`（`lua/slash_literal.lua`）：

- 空组合、中文模式下直接提交四个字符；半/全角都提交 ASCII。
- 全角提交时临时关闭 `full_shape`，提交后恢复，避免被 `shape_formatter` 变成 `＃`、`％`、`＊`、`｀`。
- 正在组合（如五笔 `*` 通配）不拦截；英文模式不拦截。
- 处理器放在 `ascii_composer` 后、`speller` 前，Shift+3 仍由 composer 处理，不会松开 Shift 时误切中英文。
- `rime_frost` 的反引号辅助码与直接 ASCII 冲突，按产品要求让空组合反引号直接上屏。
- `luna_pinyin_simp` 的 `` ` `` 笔画反查通过 `recognizer/patterns/reverse_lookup: ^$` 停用。这是唯一明确取舍。
- 中文模式不能直接输入字面量 `/gif`；需要时切英文模式。

## `/fh` 面板

Squirrel 在 Rime 处理按键后读取精确原始输入 `/fh`，清除组合标记文字，再显示非激活面板；`/fh` 不留在宿主输入框。面板使用现有 158 个非 ASCII 符号，支持中文名、英文 Unicode 名、全拼、拼音首字母和 hex 搜索。

- 左侧分类：商标与版权、警示与标志、自然与地点、体育与娱乐、方向与手势、工具与科学、其他。
- 顶部只读查询行由输入控制器驱动，不创建第二个 Rime 组合，不抢焦点。
- `↑↓←→` 移动，`PageUp/PageDown` 翻页，`Tab/Shift-Tab` 切分类，`Return` 插入，`Esc` 先清查询再关闭；空查询 Backspace 关闭。
- 鼠标首次点击即可选中；符号点击直接插入。插入走 `commit(string:)`，保留中英文空格和宿主范围校验。
- 面板打开时吞掉 `flagsChanged`，避免单按 Shift 切中英文；Command/Control/Option 组合仍交给宿主。
- 不调用 `NSApp.activate`、`makeKeyAndOrderFront`，查询行不成为第一响应者；`canBecomeKey`/`canBecomeMain=false`。切输入源、失焦、切前台、英文模式或开始语音时关闭。

## `/gif` 面板

同一 900×640 非激活面板。英文关键词 300 ms 防抖搜索；静态首帧缩略图；`PageDown` 到底继续加载，按 id 去重追加。

- 选中后下载完整 GIF（上限 20 MB），写 `~/Library/Caches/im.rime.inputmethod.Squirrel/GIFSearch/<sha256>.gif`（目录 0700、文件 0600、原子替换）。
- 剪贴板同时写 `fileURL`、`com.compuserve.gif`、首帧 TIFF/PNG、来源 URL；成功后提示“已复制 GIF；回到输入框按 ⌘V 粘贴”，短暂关闭。
- **不自动粘贴**，不通过 IMK/AX 往宿主插图或文字。
- ephemeral URLSession、无 Cookie/凭证缓存、8/20 秒超时、不跟随重定向；JSON 上限 2 MB、缩略图 5 MB。媒体/endpoint 必须 HTTPS，拒绝 loopback、私有地址、带用户名密码 URL 和 `.local`；Giphy/Tenor 媒体 host 限各自域名，自定义 provider 接受安全 HTTPS host。
- 安全输入模式下不发起搜索；已显示结果不主动刷新。
- 搜索词会发给所选服务；API Key 只存 Keychain `im.rime.inputmethod.Squirrel.GIFSearch` / `apiKey`，不写配置/日志/安装包；程序不记录 query、Key、endpoint 或响应正文。
- 启动清理 7 天前或超过 100 MB 缓存。

### 配置

输入法菜单 → **GIF 搜索设置…**（面板右下角也可打开）：

| Provider | 地址 | Key |
|---|---|---|
| Giphy | `https://api.giphy.com/v1/gifs/search`（可代理） | 必填 |
| Tenor | `https://tenor.googleapis.com/v2/search`（可代理） | 必填 |
| 自定义/代理 | 完整 HTTPS 搜索 URL | 可选，`Authorization: Bearer` |

自定义响应：

```json
{
  "items": [{
    "id": "unique-id",
    "title": "optional",
    "thumbnail_url": "https://…/thumb.gif",
    "gif_url": "https://…/full.gif",
    "width": 480,
    "height": 270,
    "source_url": "https://…/page"
  }],
  "next_offset": 24,
  "has_more": true
}
```

请求 `GET {endpoint}?q=…&limit=24&offset=…`。设置页“测试连接”固定搜索 `hello`，不显示 Key/响应正文。Giphy/Tenor 在中国大陆可能不可达；自定义 endpoint 是主路径。内容分级默认“适中”。

## 配置与部署

源码：

- `lua/slash_literal.lua`
- `wubi86.custom.yaml`、`rime_frost.custom.yaml`、`luna_pinyin_simp.custom.yaml`
- `tools/generate_symbol_catalog.py` → `native/voice/SlashSymbolData.swift`

新电脑安装 PKG 即可，`prepare_release_data.sh` 会把这些文件放入 `SharedSupport`，`rime_frost.custom.yaml` 使用 `"punctuator/symbols/+"` 合并，保留 `/bq`、`/mac` 和预设类别。生产机器不要再用 dotfiles 软链覆盖包内默认值；旧机器迁移见 [sync](sync.md)。

开发者只改源码时，可在一台源码维护机上临时链接/复制 Lua 并 `Squirrel --reload` 验证，但不要把这个模式当成部署方式。

## 验证

```sh
bash rime/tools/test_slash_palette.sh
bash rime/tools/test_voice_preferences.sh
python3 rime/tests/verify_slash.py "/Library/Input Methods/Squirrel.app"
python3 rime/tests/release_defaults_test.py \
  rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
```

`test_slash_palette.sh` 验证状态机、158 条目录、Giphy/Tenor/custom 解析、错误不泄露 Key、GIF 校验/缓存权限/剪贴板类型、面板非激活和位置钳制，并检查 `SlashSymbolData.swift` 未漂移。`verify_slash.py` 用隔离 librime 用户目录验证三个方案直接 ASCII、`/fh`、`/bq`、`/mac`、`/gif` 和 luna 取舍；使用仓库 `distribution/data` 覆盖安装包旧数据。

`rime_frost` 无头符号候选在缺少 Lua 辅助文件时可能为空，但 `/fh` 原始输入保持完整、原生面板仍打开；脚本只检查它的原始触发，对 `wubi86`/`luna_pinyin_simp` 检查完整 158 项。真实 TextEdit/Finder/Safari/iTerm2/微信/QQ 的焦点、插入和 ⌘V 仍需人工验收。
